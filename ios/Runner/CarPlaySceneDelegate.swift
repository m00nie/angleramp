import CarPlay
import UIKit

// MARK: - Theme colours matching the dark navy / emerald-green app palette
private extension UIColor {
    /// Primary interactive colour – emerald green (#34D399)
    static let cpGreen  = UIColor(red: 0x34/255.0, green: 0xD3/255.0, blue: 0x99/255.0, alpha: 1.0)
    /// Secondary blue (#60A5FA)
    static let cpBlue   = UIColor(red: 0x60/255.0, green: 0xA5/255.0, blue: 0xFA/255.0, alpha: 1.0)
    /// Dark navy surface (#080F1E)
    static let cpNavy   = UIColor(red: 0x08/255.0, green: 0x0F/255.0, blue: 0x1E/255.0, alpha: 1.0)
}

// MARK: - Tab type abstraction
private enum CarPlayTab: String, CaseIterable {
    case albums     = "albums"
    case artists    = "artists"
    case songs      = "songs"
    case playlists  = "playlists"
    case audiobooks = "audiobooks"
    case folders    = "folders"

    var title: String {
        switch self {
        case .albums:     return "Albums"
        case .artists:    return "Artists"
        case .songs:      return "Songs"
        case .playlists:  return "Playlists"
        case .audiobooks: return "Audiobooks"
        case .folders:    return "Folders"
        }
    }

    /// SF Symbol matching app's view_icon.dart
    var symbolName: String {
        switch self {
        case .albums:     return "square.stack"
        case .artists:    return "music.mic"
        case .songs:      return "music.note"
        case .playlists:  return "music.note.list"
        case .audiobooks: return "books.vertical"
        case .folders:    return "folder"
        }
    }

    /// Jellyfin includeItemTypes matching _includeItemTypes() in Flutter
    var includeItemTypes: String {
        switch self {
        case .albums:     return "MusicAlbum"
        case .artists:    return "MusicArtist"
        case .songs:      return "Audio"
        case .playlists:  return "Playlist"
        case .audiobooks: return "AudioBook"
        case .folders:    return "Folder"
        }
    }
}

// MARK: - CarPlay Scene Delegate
// Registered in Info.plist as CPTemplateApplicationSceneSessionRoleApplication.
// UIApplicationSupportsMultipleScenes = false ensures the main Flutter window
// keeps using UIApplicationDelegate lifecycle — only the CarPlay scene uses
// UISceneDelegate. This is the correct pattern for iOS 14+ CarPlay.
@available(iOS 14.0, *)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var carPlayController: CarPlayController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        NSLog("[CarPlay] Scene connected — setting up channel and controller")
        // Ensure the Flutter MethodChannel is ready before creating the controller.
        (UIApplication.shared.delegate as? AppDelegate)?.setupCarPlayChannel()
        let ch = (UIApplication.shared.delegate as? AppDelegate)?.carPlayChannel
        NSLog("[CarPlay] Channel after setup: \(ch == nil ? "NIL" : "OK")")
        carPlayController = CarPlayController(interfaceController: interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        NSLog("[CarPlay] Scene disconnected")
        carPlayController?.disconnect()
        carPlayController = nil
    }
}

// MARK: - CarPlay Controller
// Owned by CarPlaySceneDelegate. Handles all CarPlay UI logic.
@available(iOS 14.0, *)
class CarPlayController: NSObject {

    private let interfaceController: CPInterfaceController

    // Small LRU-style image cache
    private var imageCache: [String: UIImage] = [:]
    private var imageTasks: [String: URLSessionDataTask] = [:]

    /// Track whether we have already registered as a CPNowPlayingTemplate observer.
    private var nowPlayingObserverAdded = false

    // Reference back to the Flutter MethodChannel stored on AppDelegate
    private var channel: FlutterMethodChannel? {
        (UIApplication.shared.delegate as? AppDelegate)?.carPlayChannel
    }

    // MARK: - Lifecycle

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        super.init()
        applyTheme()
        buildRootTabBar()
    }

    func disconnect() {
        imageTasks.values.forEach { $0.cancel() }
        imageTasks.removeAll()
        imageCache.removeAll()
    }

    // MARK: - Theme

    /// Apply emerald-green tint to the CarPlay navigation chrome.
    private func applyTheme() {
        UINavigationBar.appearance().tintColor = .cpGreen
    }

    // MARK: - Root template

    private func buildRootTabBar() {
        // Set a placeholder immediately so CarPlay's watchdog is satisfied
        // before any async work (channel call, Jellyfin request) completes.
        let placeholder = CPListTemplate(title: "AnglerAmp", sections: [])
        placeholder.emptyViewTitleVariants    = ["Loading…"]
        placeholder.emptyViewSubtitleVariants = ["Connecting to your library"]
        // Don't rely solely on the completion block — it has known simulator
        // timing issues. Call directly on the next run-loop tick instead.
        interfaceController.setRootTemplate(placeholder, animated: false)
        DispatchQueue.main.async { [weak self] in
            self?.loadTabsFromFlutter(retryCount: 0)
        }
    }

    /// Retry up to 5 times (0.5 s apart) waiting for the Flutter channel to
    /// become available. In practice the engine is always ready within 1 s.
    private func loadTabsFromFlutter(retryCount: Int) {
        guard let channel = channel else {
            guard retryCount < 5 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.loadTabsFromFlutter(retryCount: retryCount + 1)
            }
            return
        }
        loadTabsUsingChannel(channel)
    }

    private func loadTabsUsingChannel(_ channel: FlutterMethodChannel) {
        channel.invokeMethod("getEnabledTabs", arguments: nil) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let maxTabs = CPTabBarTemplate.maximumTabCount
                NSLog("[CarPlay] maximumTabCount=\(maxTabs), result=\(String(describing: result))")

                let tabNames = (result as? [String]) ?? ["albums", "artists", "songs", "playlists"]
                // Cap to CPTabBarTemplate.maximumTabCount (audio apps typically get 4;
                // using a hardcoded 5 can exceed the limit and throw a fatal exception).
                let tabs = Array(tabNames.compactMap { CarPlayTab(rawValue: $0) }.prefix(maxTabs))
                NSLog("[CarPlay] Resolved \(tabs.count) tabs: \(tabs.map(\.rawValue))")

                if tabs.count >= 2 {
                    let templates = tabs.map { self.makeRootListTemplate(for: $0) }
                    // Log each template's validation-critical properties.
                    for (i, t) in templates.enumerated() {
                        NSLog("[CarPlay] Tab[\(i)] tabTitle='\(t.tabTitle ?? "nil")' tabImage=\(t.tabImage == nil ? "NIL" : "OK")")
                    }
                    let tabBar = CPTabBarTemplate(templates: templates)
                    tabBar.delegate = self
                    self.interfaceController.setRootTemplate(tabBar, animated: false) { _, _ in }
                } else {
                    // Only 1 tab enabled (or no response): show it directly.
                    let tab = tabs.first ?? .albums
                    let template = self.makeRootListTemplate(for: tab)
                    self.interfaceController.setRootTemplate(template, animated: false) { _, _ in }
                }
            }
        }
    }

    // MARK: - List template factory

    private func makeRootListTemplate(for tab: CarPlayTab) -> CPListTemplate {
        let template = buildListTemplate(title: tab.title, symbolName: tab.symbolName)
        template.tabTitle = tab.title
        template.tabImage = tintedSymbol(tab.symbolName, color: .cpGreen)
        setLoadingState(template)

        loadItems(tab: tab, parentId: nil, parentType: nil, into: template)
        return template
    }

    private func buildListTemplate(title: String, symbolName: String) -> CPListTemplate {
        let t = CPListTemplate(title: title, sections: [])
        t.emptyViewTitleVariants    = ["Nothing here"]
        t.emptyViewSubtitleVariants = ["Check your Jellyfin connection"]
        return t
    }

    // MARK: - Data loading

    /// Fetch items from Dart and populate the template.
    private func loadItems(
        tab: CarPlayTab,
        parentId: String?,
        parentType: String?,
        into template: CPListTemplate,
        completion: (([[String: Any]]) -> Void)? = nil
    ) {
        setLoadingState(template)

        var args: [String: Any] = ["tabType": tab.rawValue]
        if let pid = parentId   { args["parentId"]   = pid }
        if let pt  = parentType { args["parentType"] = pt  }

        channel?.invokeMethod("getItems", arguments: args) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let items = (result as? [[String: Any]]) ?? []

                if items.isEmpty {
                    template.emptyViewTitleVariants    = ["No items"]
                    template.emptyViewSubtitleVariants = ["Your library appears to be empty"]
                    template.updateSections([])
                    completion?([])
                    return
                }

                let (section, listItems) = self.buildSection(items: items, tab: tab)
                template.updateSections([section])
                completion?(items)

                // Fire off album-art loading in background
                self.loadArtwork(items: items, listItems: listItems, template: template)
            }
        }
    }

    // MARK: - Section / item building

    private func buildSection(
        items: [[String: Any]],
        tab: CarPlayTab
    ) -> (CPListSection, [CPListItem]) {
        var listItems: [CPListItem] = []

        for (index, item) in items.enumerated() {
            let listItem = buildListItem(item: item, tab: tab, allItems: items, indexInParent: index)
            listItems.append(listItem)
        }

        let section = CPListSection(items: listItems)
        return (section, listItems)
    }

    private func buildListItem(
        item: [String: Any],
        tab: CarPlayTab,
        allItems: [[String: Any]],
        indexInParent: Int
    ) -> CPListItem {
        let name   = item["name"]        as? String ?? "Unknown"
        let type   = item["type"]        as? String ?? ""
        let artist = item["albumArtist"] as? String
            ?? (item["artists"] as? [String])?.joined(separator: ", ")

        let isBrowsable = ["MusicAlbum", "MusicArtist", "MusicGenre",
                           "Playlist", "AudioBook", "Folder"].contains(type)

        // Tiny emerald-tinted placeholder icon
        let placeholder = tintedSymbol(tab.symbolName, color: .cpGreen, size: 44)

        let listItem = CPListItem(
            text: name,
            detailText: artist,
            image: placeholder,
            accessoryImage: nil,
            accessoryType: isBrowsable ? .disclosureIndicator : .none
        )

        // ── Tap handler ── capture item data in the closure
        listItem.handler = { [weak self] _, done in
            guard let self = self else { done(); return }
            self.handleTap(item: item, tab: tab, allItems: allItems, indexInParent: indexInParent)
            done()
        }

        return listItem
    }

    // MARK: - Tap handling

    private func handleTap(
        item: [String: Any],
        tab: CarPlayTab,
        allItems: [[String: Any]],
        indexInParent: Int
    ) {
        let type = item["type"] as? String ?? ""
        let id   = item["id"]   as? String ?? ""
        let name = item["name"] as? String ?? "Items"

        switch type {

        case "Audio":
            // Play the whole list from the tapped index
            startPlayback(items: allItems, startIndex: indexInParent)

        case "MusicAlbum", "Playlist", "AudioBook":
            // Push a track list, then play whole container from tapped track
            pushDrillTemplate(title: name, tab: .songs, parentId: id, parentType: type)

        case "MusicArtist":
            pushDrillTemplate(title: name, tab: .albums, parentId: id, parentType: type)

        case "MusicGenre":
            pushDrillTemplate(title: name, tab: .albums, parentId: id, parentType: type)

        case "Folder":
            pushDrillTemplate(title: name, tab: .folders, parentId: id, parentType: type)

        default:
            break
        }
    }

    private func pushDrillTemplate(
        title: String,
        tab: CarPlayTab,
        parentId: String,
        parentType: String
    ) {
        let drillTemplate = buildListTemplate(title: title, symbolName: tab.symbolName)
        setLoadingState(drillTemplate)

        interfaceController.pushTemplate(drillTemplate, animated: true) { _, _ in }

        loadItems(tab: tab, parentId: parentId, parentType: parentType, into: drillTemplate) { [weak self] items in
            guard let self = self else { return }
            // Re-build items so that tapping a song plays the whole album from that index
            if tab == .songs || (tab == .folders && items.allSatisfy({ ($0["type"] as? String) == "Audio" }) ) {
                self.rewireForAlbumPlayback(template: drillTemplate, items: items, tab: tab)
            }
        }
    }

    /// After a track list is loaded, update every item's handler so tapping
    /// plays the full album/playlist from that position.
    private func rewireForAlbumPlayback(
        template: CPListTemplate,
        items: [[String: Any]],
        tab: CarPlayTab
    ) {
        let allListItems = template.sections.flatMap { $0.items as? [CPListItem] ?? [] }
        guard allListItems.count == items.count else { return }

        for (index, listItem) in allListItems.enumerated() {
            let captured = items         // capture full list
            let idx      = index
            listItem.handler = { [weak self] _, done in
                guard let self = self else { done(); return }
                self.startPlayback(items: captured, startIndex: idx)
                done()
            }
        }
    }

    // MARK: - Playback

    private func startPlayback(items: [[String: Any]], startIndex: Int) {
        let args: [String: Any] = [
            "items": items,
            "startIndex": startIndex,
        ]
        channel?.invokeMethod("playItems", arguments: args) { _ in }

        // Present Now Playing template — register observer only once per session.
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.isUpNextButtonEnabled         = true
        nowPlaying.isAlbumArtistButtonEnabled    = false
        if !nowPlayingObserverAdded {
            nowPlaying.add(self)
            nowPlayingObserverAdded = true
        }
        interfaceController.pushTemplate(nowPlaying, animated: true) { _, _ in }
    }

    // MARK: - Artwork loading

    private func loadArtwork(
        items: [[String: Any]],
        listItems: [CPListItem],
        template: CPListTemplate
    ) {
        for (idx, item) in items.prefix(listItems.count).enumerated() {
            guard let urlStr = item["imageUrl"] as? String,
                  let url    = URL(string: urlStr) else { continue }

            if let cached = imageCache[urlStr] {
                applyImage(cached, to: listItems[idx], template: template)
                continue
            }

            let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self = self,
                      let data = data,
                      let img  = UIImage(data: data) else { return }

                let sized = self.resize(img, to: CGSize(width: 58, height: 58))
                self.imageCache[urlStr] = sized

                DispatchQueue.main.async {
                    guard idx < listItems.count else { return }
                    self.applyImage(sized, to: listItems[idx], template: template)
                }
            }
            imageTasks[urlStr] = task
            task.resume()
        }
    }

    private func applyImage(_ image: UIImage, to item: CPListItem, template: CPListTemplate) {
        item.setImage(image)
        // Poke the template to redraw
        if !template.sections.isEmpty {
            template.updateSections(template.sections)
        }
    }

    // MARK: - Helpers

    private func setLoadingState(_ template: CPListTemplate) {
        template.emptyViewTitleVariants    = ["Loading…"]
        template.emptyViewSubtitleVariants = ["Fetching from Jellyfin"]
        template.updateSections([])
    }

    private func tintedSymbol(_ name: String, color: UIColor, size: CGFloat = 36) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: size * 0.6, weight: .regular)
        return UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
    }

    private func resize(_ image: UIImage, to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - CPTabBarTemplateDelegate
@available(iOS 14.0, *)
extension CarPlayController: CPTabBarTemplateDelegate {
    func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        // Content already loaded at template creation; nothing extra needed.
    }
}

// MARK: - CPNowPlayingTemplateObserver
@available(iOS 14.0, *)
extension CarPlayController: CPNowPlayingTemplateObserver {
    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        // Future: push a queue template
    }

    func nowPlayingTemplateAlbumArtistButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        // Future: push the artist's albums
    }
}
