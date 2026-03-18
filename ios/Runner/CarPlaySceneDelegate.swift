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

    /// Apply the app's dark navy / emerald-green palette to all CarPlay chrome.
    ///
    /// Flutter renders entirely inside a custom Metal view, so UIAppearance
    /// changes here only affect the CarPlay template UI — not the phone screen.
    /// `configureWithOpaqueBackground()` explicitly opts out of iOS 26's
    /// translucent "Liquid Glass" design in favour of our solid colours.
    private func applyTheme() {
        // ── Navigation bar ────────────────────────────────────────────────
        let navAp = UINavigationBarAppearance()
        navAp.configureWithOpaqueBackground()
        navAp.backgroundColor = .cpNavy
        navAp.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
        ]
        navAp.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        // Back button chevron colour
        navAp.setBackIndicatorImage(
            UIImage(systemName: "chevron.left"),
            transitionMaskImage: UIImage(systemName: "chevron.left")
        )
        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance   = navAp
        navBar.scrollEdgeAppearance = navAp
        navBar.compactAppearance    = navAp
        navBar.tintColor            = .cpGreen   // back chevron + bar buttons

        // ── Tab bar ───────────────────────────────────────────────────────
        let tabAp = UITabBarAppearance()
        tabAp.configureWithOpaqueBackground()
        tabAp.backgroundColor = .cpNavy
        let tabItem = UITabBarItemAppearance()
        tabItem.selected.iconColor  = .cpGreen
        tabItem.selected.titleTextAttributes  = [.foregroundColor: UIColor.cpGreen]
        tabItem.normal.iconColor    = UIColor(white: 0.55, alpha: 1)
        tabItem.normal.titleTextAttributes    = [.foregroundColor: UIColor(white: 0.55, alpha: 1)]
        tabAp.stackedLayoutAppearance = tabItem
        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance   = tabAp
        tabBar.tintColor            = .cpGreen
        tabBar.unselectedItemTintColor = UIColor(white: 0.55, alpha: 1)
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
                NSLog("[CarPlay] maximumTabCount=\(maxTabs)")
                let tabNames = (result as? [String]) ?? ["albums", "artists", "songs", "playlists"]
                let allTabs  = tabNames.compactMap { CarPlayTab(rawValue: $0) }

                // Audiobooks and folders always live in the Browse / Library tab
                // so they are always reachable regardless of which tabs are
                // configured and regardless of the 4-tab cap.
                let musicTabs    = allTabs.filter { $0 != .audiobooks && $0 != .folders }
                let mainTabs     = Array(musicTabs.prefix(maxTabs - 1))
                // Any music tabs that didn't fit go into Browse as menu items.
                let overflowTabs = Array(musicTabs.dropFirst(maxTabs - 1))

                NSLog("[CarPlay] mainTabs=\(mainTabs.map(\.rawValue)) overflow=\(overflowTabs.map(\.rawValue))")

                var templates: [CPListTemplate] = mainTabs.map { self.makeRootListTemplate(for: $0) }
                templates.append(self.makeBrowseTemplate(overflow: overflowTabs))

                if templates.count >= 2 {
                    let tabBar = CPTabBarTemplate(templates: templates)
                    tabBar.delegate = self
                    self.interfaceController.setRootTemplate(tabBar, animated: false) { _, _ in }
                } else {
                    // Edge-case: 0 music tabs → show Browse directly (no tab bar)
                    self.interfaceController.setRootTemplate(
                        templates.first ?? self.makeBrowseTemplate(overflow: []),
                        animated: false
                    ) { _, _ in }
                }
            }
        }
    }

    // MARK: - Browse / Library tab

    /// The always-present last tab. Contains Audiobooks, folder navigation, and
    /// any music tabs that were pushed off by the `maximumTabCount` limit.
    private func makeBrowseTemplate(overflow: [CarPlayTab]) -> CPListTemplate {
        var items: [CPListItem] = []

        // Overflow music tabs (e.g. Playlists when the 4-tab cap is reached)
        for tab in overflow {
            items.append(makeBrowseMenuItem(title: tab.title, symbol: tab.symbolName) { [weak self] in
                guard let self = self else { return }
                let tpl = self.buildListTemplate(title: tab.title, symbolName: tab.symbolName)
                self.setLoadingState(tpl)
                self.interfaceController.pushTemplate(tpl, animated: true) { _, _ in }
                self.loadItems(tab: tab, parentId: nil, parentType: nil, into: tpl)
            })
        }

        // Audiobooks — always present
        items.append(makeBrowseMenuItem(
            title: "Audiobooks",
            symbol: "books.vertical",
            detail: "Browse your audiobook library"
        ) { [weak self] in
            guard let self = self else { return }
            let tpl = self.buildListTemplate(title: "Audiobooks", symbolName: "books.vertical")
            self.setLoadingState(tpl)
            self.interfaceController.pushTemplate(tpl, animated: true) { _, _ in }
            self.loadItems(tab: .audiobooks, parentId: nil, parentType: nil, into: tpl)
        })

        // Folder browser — always present
        items.append(makeBrowseMenuItem(
            title: "Browse by Folder",
            symbol: "folder",
            detail: "Navigate your media by directory"
        ) { [weak self] in
            guard let self = self else { return }
            let tpl = self.buildListTemplate(title: "Browse by Folder", symbolName: "folder")
            self.setLoadingState(tpl)
            self.interfaceController.pushTemplate(tpl, animated: true) { _, _ in }
            self.loadItems(tab: .folders, parentId: nil, parentType: nil, into: tpl)
        })

        let section  = CPListSection(items: items)
        let template = CPListTemplate(title: "Library", sections: [section])
        template.tabTitle = "Library"
        template.tabImage = tintedSymbol("books.vertical.fill", color: .cpGreen)
        return template
    }

    /// Build a single disclosure-style row for use in the Browse/Library tab.
    private func makeBrowseMenuItem(
        title: String,
        symbol: String,
        detail: String? = nil,
        action: @escaping () -> Void
    ) -> CPListItem {
        let item = CPListItem(
            text: title,
            detailText: detail,
            image: tintedSymbol(symbol, color: .cpGreen, size: 44),
            accessoryImage: nil,
            accessoryType: .disclosureIndicator
        )
        item.handler = { _, done in
            action()
            done()
        }
        return item
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
    /// - Parameter path: For folder drilling, the file-system path of the
    ///   parent directory (needed by `JellyfinApiHelper` to locate children).
    private func loadItems(
        tab: CarPlayTab,
        parentId: String?,
        parentType: String?,
        path: String? = nil,
        into template: CPListTemplate,
        completion: (([[String: Any]]) -> Void)? = nil
    ) {
        setLoadingState(template)

        var args: [String: Any] = ["tabType": tab.rawValue]
        if let pid = parentId   { args["parentId"]   = pid }
        if let pt  = parentType { args["parentType"] = pt  }
        if let p   = path       { args["parentPath"] = p   }

        channel?.invokeMethod("getItems", arguments: args) { [weak self] result in
            guard let self = self else { return }
            // Surface Dart-side errors so they appear in Console rather than
            // silently becoming an empty list.
            if let err = result as? FlutterError {
                NSLog("[CarPlay] getItems error for tab=%@ parentType=%@: %@ – %@",
                      tab.rawValue, parentType ?? "nil", err.code, err.message ?? "")
            }
            DispatchQueue.main.async {
                let items = (result as? [[String: Any]]) ?? []
                NSLog("[CarPlay] getItems: %d item(s) tab=%@ parentType=%@ parentId=%@",
                      items.count, tab.rawValue, parentType ?? "nil", parentId ?? "nil")

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
            let path = item["path"] as? String
            pushDrillTemplate(title: name, tab: .folders, parentId: id, parentType: type, path: path)

        default:
            break
        }
    }

    private func pushDrillTemplate(
        title: String,
        tab: CarPlayTab,
        parentId: String,
        parentType: String,
        path: String? = nil
    ) {
        let drillTemplate = buildListTemplate(title: title, symbolName: tab.symbolName)
        setLoadingState(drillTemplate)

        interfaceController.pushTemplate(drillTemplate, animated: true) { _, _ in }

        loadItems(tab: tab, parentId: parentId, parentType: parentType,
                  path: path, into: drillTemplate) { [weak self] items in
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

                let sized = self.resize(img, to: CGSize(width: 80, height: 80), cornerRadius: 6)
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

    private func resize(_ image: UIImage, to size: CGSize, cornerRadius: CGFloat = 0) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            if cornerRadius > 0 {
                UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
            }
            image.draw(in: rect)
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
