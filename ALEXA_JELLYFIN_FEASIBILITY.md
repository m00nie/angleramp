# Feasibility Study: Alexa Skill with Mobile-Phone Pairing for Jellyfin Audio Library Browsing

> **Context**: This document examines whether it is possible to build an Alexa skill — similar in spirit to the AnglerAmp / Finamp mobile app — that pairs with a user's mobile phone to configure Jellyfin integration and then allows the user to browse their Jellyfin audio library via voice (and optionally via an Echo Show screen).

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [AnglerAmp / Finamp Architecture Overview](#2-angleramp--finamp-architecture-overview)
3. [Relevant Alexa Skill Types](#3-relevant-alexa-skill-types)
4. [Mobile-Phone Pairing: Account Linking & App-to-App Flow](#4-mobile-phone-pairing-account-linking--app-to-app-flow)
5. [Jellyfin API Compatibility with Alexa](#5-jellyfin-api-compatibility-with-alexa)
6. [Audio Library Browsing on Alexa](#6-audio-library-browsing-on-alexa)
7. [Existing Jellyfin–Alexa Projects (Prior Art)](#7-existing-jellyfinalexaprojects-prior-art)
8. [Proposed Architecture](#8-proposed-architecture)
9. [Challenges and Limitations](#9-challenges-and-limitations)
10. [Verdict](#10-verdict)
11. [References](#11-references)

---

## 1. Executive Summary

**Yes — it is feasible**, with meaningful caveats.

A custom Alexa skill can authenticate against a user's Jellyfin server, browse the audio library by album / artist / playlist / genre, and stream audio to Alexa-enabled devices using the AudioPlayer interface. Mobile-phone pairing is achievable through Amazon's **App-to-App Account Linking** (OAuth 2.0 with PKCE), which lets a Flutter companion app (like AnglerAmp) hand Jellyfin credentials to the Alexa skill without the user re-entering them manually.

Several community projects have already demonstrated core playback, though none yet offer deep hierarchical browsing or mobile-phone–driven setup. The primary constraints are: (a) the Jellyfin server must be HTTPS-accessible from the internet, (b) audio files must be streamable via HTTPS URLs, and (c) voice-only browsing of large libraries is inherently shallow compared to a visual mobile app.

---

## 2. AnglerAmp / Finamp Architecture Overview

AnglerAmp is a Flutter (Dart) mobile app for iOS and Android that connects to a self-hosted Jellyfin media server. Understanding its architecture is essential because it defines **what data and APIs are available** for an Alexa skill to reuse.

### 2.1 Jellyfin Connection

| Component | Detail |
|-----------|--------|
| **Authentication** | `POST /Users/AuthenticateByName` with `{ "Username", "Pw" }` → returns `AccessToken` + `User.Id` + `ServerId` |
| **Token usage** | All requests carry `Authorization: MediaBrowser Token="<token>", Client="…", Device="…", DeviceId="…", Version="…"` |
| **REST client** | Chopper-based `JellyfinApi` service (`lib/services/jellyfin_api.dart`, 450 lines) |
| **API helper** | `JellyfinApiHelper` wraps Chopper calls with business logic (`lib/services/jellyfin_api_helper.dart`, 607 lines) |
| **Persistence** | Hive database stores `FinampUser` (id, baseUrl, accessToken, serverId, views) |

### 2.2 Audio Library Browsing

AnglerAmp exposes seven browse tabs through `TabContentType`:

| Tab | Jellyfin `IncludeItemTypes` | Notes |
|-----|-----------------------------|-------|
| Albums | `MusicAlbum` | Standard album browsing |
| Artists | `MusicArtist` | Drill into artist → albums → tracks |
| Songs | `Audio` | Flat list of all audio tracks |
| Playlists | `Playlist` | User-created playlists |
| Genres | `MusicGenre` | Browse by genre |
| Audiobooks | `AudioBook` | AnglerAmp-specific addition |
| Folders | `Folder` | Directory-based navigation (AnglerAmp-specific) |

**Key API endpoints used by the app:**
- `GET /Users/{userId}/Views` — list library views
- `GET /Users/{userId}/Items?parentId={id}&IncludeItemTypes=…` — fetch items
- `GET /Artists/AlbumArtists` — list album artists
- `GET /Genres` — list genres
- `GET /Audio/{itemId}/universal` — stream audio

### 2.3 CarPlay Integration (Closest Analogy)

AnglerAmp already has a **CarPlay integration** (`lib/services/carplay_service.dart`) that acts as a platform bridge — receiving requests from native iOS (Swift) over a MethodChannel and responding with Jellyfin data. This is architecturally very similar to what an Alexa skill backend would need to do:

```
CarPlay (iOS native)  ←→  MethodChannel  ←→  Dart JellyfinApiHelper  ←→  Jellyfin Server
```

An Alexa skill would follow the same pattern, but with the bridge going over HTTPS instead of a MethodChannel:

```
Alexa Voice Service  ←→  HTTPS  ←→  Skill Backend  ←→  Jellyfin Server
```

The CarPlay service demonstrates that the Jellyfin API already provides everything needed: tab enumeration, hierarchical item browsing, and playback initiation.

---

## 3. Relevant Alexa Skill Types

Amazon offers several skill APIs. The correct choice depends on the use case:

### 3.1 Custom Skill + AudioPlayer Interface ✅ (Best fit)

| Aspect | Detail |
|--------|--------|
| **What it is** | A fully custom voice interaction model with the AudioPlayer interface for long-form streaming |
| **Browsing** | Define custom intents and slots: `BrowseAlbumsIntent`, `PlayArtistIntent`, `SearchSongIntent`, etc. |
| **Playback** | `AudioPlayer.Play` directive sends an HTTPS URL; Alexa handles buffering, play/pause/next |
| **Visual** | Alexa Presentation Language (APL) for screen-enabled devices (Echo Show): scrollable lists, album art, metadata cards |
| **Account Linking** | Full OAuth 2.0 support, including App-to-App linking |
| **Hosting** | AWS Lambda or self-hosted HTTPS endpoint (port 443, valid SSL) |

**Why this is the best fit:** It offers maximum flexibility — custom voice intents for browsing, the AudioPlayer for streaming, APL for visual browsing on screen devices, and full account linking for mobile pairing. This is what existing Jellyfin–Alexa projects use.

### 3.2 Music Skill API ❌ (Not suitable)

The Music Skill API is designed for **commercial streaming partners** (Spotify, Pandora, etc.). It requires:
- Amazon partnership agreement
- Regular catalog metadata ingestion by Amazon
- Compliance with music service policies

Personal/self-hosted libraries are **not eligible** for this API.

### 3.3 Smart Home Skill API ❌ (Not suitable)

Designed for IoT device control (lights, thermostats), not audio browsing or playback.

---

## 4. Mobile-Phone Pairing: Account Linking & App-to-App Flow

This is the core question: **can a mobile app (like AnglerAmp) pair with the Alexa skill to configure Jellyfin access?**

### 4.1 How It Works

Amazon provides two App-to-App Account Linking flows:

#### Flow A: Starting from the Mobile App (Recommended)

```
┌─────────────┐     ┌───────────────┐     ┌──────────────┐     ┌──────────────┐
│  AnglerAmp  │────▶│ OAuth Server  │────▶│  Alexa App   │────▶│ Skill Linked │
│  (Flutter)  │     │ (your backend)│     │  (on phone)  │     │  with Token  │
└─────────────┘     └───────────────┘     └──────────────┘     └──────────────┘

1. User taps "Link to Alexa" in AnglerAmp
2. App launches OAuth authorization URL with PKCE challenge
3. OAuth server authenticates (reusing existing Jellyfin session)
4. Redirect to Alexa app via Universal Link / App Link
5. Alexa app exchanges auth code for access token
6. Skill now has an OAuth token that maps to Jellyfin credentials
```

#### Flow B: Starting from the Alexa App

```
┌─────────────┐     ┌───────────────┐     ┌──────────────┐     ┌──────────────┐
│  Alexa App  │────▶│ OAuth Server  │────▶│  AnglerAmp   │────▶│ Skill Linked │
│  (on phone) │     │ (login page)  │     │  (optional)  │     │  with Token  │
└─────────────┘     └───────────────┘     └──────────────┘     └──────────────┘

1. User enables skill in Alexa app
2. Alexa app opens OAuth login page in a WebView
3. User enters Jellyfin server URL + credentials
4. OAuth server issues token, redirects back to Alexa
5. Skill linked
```

### 4.2 What Needs to Be Built

| Component | Description | Complexity |
|-----------|-------------|------------|
| **OAuth 2.0 Server** | Lightweight server that authenticates against Jellyfin and issues OAuth tokens. Could be a thin wrapper around Jellyfin's `/Users/AuthenticateByName` | Medium |
| **Universal/App Links** | iOS: `apple-app-site-association`; Android: `assetlinks.json` — hosted at a public `.well-known` URL | Low |
| **AnglerAmp UI** | "Link to Alexa" button that initiates the OAuth flow using Flutter's `uni_links` or `app_links` package | Low |
| **Alexa Developer Console** | Configure account linking with OAuth endpoints, redirect URIs, client ID/secret | Low |

### 4.3 Token Bridge Design

The OAuth server acts as a **token bridge** between Alexa and Jellyfin:

```
Alexa sends: accessToken (OAuth) → Skill Backend
Skill Backend maps: OAuth token → (jellyfinBaseUrl, jellyfinAccessToken, userId)
Skill Backend calls: Jellyfin API with user's credentials
```

This keeps the user's Jellyfin credentials secure — Alexa never sees the raw Jellyfin token, only an opaque OAuth token. The backend maintains the mapping in a database (PostgreSQL, SQLite, DynamoDB, etc.).

### 4.4 Evidence This Is Feasible

- Amazon officially documents App-to-App Account Linking with PKCE: [Starting from your app](https://developer.amazon.com/en-US/docs/alexa/account-linking/app-to-app-account-linking-starting-from-your-app.html)
- The `jellyfin_alexa_skill` project by infinityofspace already implements a simpler version (web-based OAuth, no app-to-app) and confirms the token-bridge pattern works in production
- Flutter packages `uni_links` and `app_links` support Universal Links / App Links, which are required for the redirect flow
- AnglerAmp already stores `FinampUser.accessToken` and `FinampUser.baseUrl` in Hive, so the OAuth server has the data it needs

---

## 5. Jellyfin API Compatibility with Alexa

### 5.1 Audio Streaming

Alexa's AudioPlayer interface requires audio to be served via **HTTPS URLs**. Jellyfin's universal audio endpoint provides exactly this:

```
GET https://<server>/Audio/{itemId}/universal?userId={userId}&audio_codec=mp3&container=mp3
Authorization: MediaBrowser Token="<token>", ...
```

**Compatibility check:**

| Requirement | Jellyfin Support | Status |
|-------------|-----------------|--------|
| HTTPS with valid SSL | Yes (if configured with Let's Encrypt, Caddy, etc.) | ✅ |
| MP3 or AAC format | Yes — server-side transcoding available | ✅ |
| Direct URL (no auth in body) | Token can be passed as `api_key` query param | ✅ |
| Seekable stream | Yes | ✅ |

**Important**: The audio URL sent to Alexa must include authentication. Jellyfin supports `?api_key=<token>` as a query parameter, which avoids the need for custom headers in the AudioPlayer directive.

### 5.2 Library Browsing

All browse operations that AnglerAmp performs through `JellyfinApiHelper.getItems()` are standard Jellyfin REST API calls:

| Browse Action | Jellyfin Endpoint | Alexa Intent (Custom Skill) |
|--------------|-------------------|---------------------------|
| List albums | `GET /Users/{userId}/Items?IncludeItemTypes=MusicAlbum` | `BrowseAlbumsIntent` |
| List artists | `GET /Artists/AlbumArtists` | `BrowseArtistsIntent` |
| List playlists | `GET /Users/{userId}/Items?IncludeItemTypes=Playlist` | `BrowsePlaylistsIntent` |
| List genres | `GET /Genres` | `BrowseGenresIntent` |
| Search | `GET /Users/{userId}/Items?searchTerm=…` | `SearchIntent` |
| Album tracks | `GET /Users/{userId}/Items?parentId={albumId}&IncludeItemTypes=Audio` | `PlayAlbumIntent` |

All of these are simple REST calls that a skill backend (Lambda or Flask) can make using the stored Jellyfin token.

---

## 6. Audio Library Browsing on Alexa

### 6.1 Voice-Based Browsing

Custom intents enable natural voice navigation:

```
User: "Alexa, ask Jelly Player to list my albums"
→ BrowseAlbumsIntent → Jellyfin API → "You have 342 albums. Here are the first five:
   Rumours by Fleetwood Mac, Abbey Road by The Beatles, ..."

User: "Alexa, ask Jelly Player to play Rumours"
→ PlayAlbumIntent (album="Rumours") → search Jellyfin → queue tracks → AudioPlayer.Play

User: "Alexa, ask Jelly Player to search for Beatles"
→ SearchIntent (query="Beatles") → Jellyfin search → "I found 3 albums and 47 songs
   matching Beatles. Would you like to hear Abbey Road?"
```

### 6.2 Visual Browsing (Echo Show / Fire TV)

Alexa Presentation Language (APL) enables rich visual interfaces on screen-equipped devices:

- **Scrollable lists** with album art, artist names, and track counts
- **Touch selection** — user taps an album to play it
- **Grid layouts** — similar to the mobile app's album grid
- **Now Playing** screen with album art and playback controls

APL uses JSON templates and data sources. The skill backend fetches data from Jellyfin and formats it into APL-compatible data:

```json
{
  "type": "Alexa.Presentation.APL.RenderDocument",
  "document": { /* list template */ },
  "datasources": {
    "albumList": {
      "items": [
        { "title": "Rumours", "artist": "Fleetwood Mac", "imageUrl": "https://..." },
        { "title": "Abbey Road", "artist": "The Beatles", "imageUrl": "https://..." }
      ]
    }
  }
}
```

Jellyfin provides album art URLs via `GET /Items/{id}/Images/Primary`, which can be forwarded directly to APL templates.

### 6.3 Browsing Depth Comparison

| Dimension | AnglerAmp (Mobile) | Alexa Skill (Voice) | Alexa Skill (Visual/APL) |
|-----------|-------------------|--------------------|-----------------------|
| Album browsing | Full scrollable list | Top N by voice, pagination | Scrollable list with art |
| Artist drill-down | Artist → Albums → Tracks | Multi-turn dialog | Touch navigation |
| Search | Real-time search bar | Voice query | Keyboard + voice |
| Folder browsing | Full hierarchy | Very difficult by voice | Possible with touch |
| Sorting | Per-tab sort options | Limited (voice is slow) | Dropdown/touch |
| Offline mode | Downloaded tracks | Not applicable | Not applicable |

---

## 7. Existing Jellyfin–Alexa Projects (Prior Art)

Three community projects prove core feasibility:

### 7.1 jellyfin_alexa_skill (infinityofspace)

| Attribute | Detail |
|-----------|--------|
| **GitHub** | [infinityofspace/jellyfin_alexa_skill](https://github.com/infinityofspace/jellyfin_alexa_skill) |
| **Stack** | Python, Flask, Flask-Ask SDK, PostgreSQL (Peewee ORM), Gunicorn |
| **Status** | Alpha — actively maintained |
| **Features** | Play by song/album/artist/playlist, favorites, shuffle, repeat, multi-user, multi-language |
| **Architecture** | Self-hosted Flask app ←→ Jellyfin API; Alexa Voice Service ←→ Flask app via HTTPS |
| **Account Linking** | Web-based (not app-to-app) |
| **Browsing** | Voice search and play — no deep hierarchical browsing or visual APL |

**Key takeaway**: Proves the Jellyfin API ↔ Alexa pipeline works end-to-end. Does not implement mobile pairing or visual browsing.

### 7.2 JellyMusic (Rusketh)

| Attribute | Detail |
|-----------|--------|
| **GitHub** | [Rusketh/JellyMusic](https://github.com/Rusketh/JellyMusic) |
| **Stack** | Docker-based service |
| **Features** | Play by album/song/artist/playlist/genre, per-device queues |
| **Status** | Work in progress |

### 7.3 jellyfin-alexa-plugin (infinityofspace)

| Attribute | Detail |
|-----------|--------|
| **GitHub** | [infinityofspace/jellyfin-alexa-plugin](https://github.com/infinityofspace/jellyfin-alexa-plugin) |
| **Stack** | Jellyfin server plugin (C#) |
| **Features** | Play/pause, favorites, playlists — music only |
| **Status** | Early alpha |

### 7.4 What's Missing in All Existing Projects

| Gap | Description |
|-----|-------------|
| **Mobile-phone pairing** | None use App-to-App Account Linking; all require manual configuration |
| **Visual browsing (APL)** | No project implements APL for Echo Show visual browsing |
| **Deep hierarchical browsing** | All support "play X" — none support multi-turn "browse → drill → select" voice flows |
| **Audiobook support** | None support AnglerAmp's audiobook browsing |
| **Folder browsing** | None support AnglerAmp's directory-based navigation |

---

## 8. Proposed Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                        USER'S ENVIRONMENT                            │
│                                                                      │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────────────┐  │
│  │  AnglerAmp  │    │  Alexa App   │    │   Echo / Echo Show     │  │
│  │  (Flutter)  │    │  (on phone)  │    │   (voice + screen)     │  │
│  └──────┬──────┘    └──────┬───────┘    └───────────┬────────────┘  │
│         │                  │                        │               │
│         │  (1) App-to-App  │                        │               │
│         │  Account Linking │                        │               │
│         └──────────────────┘                        │               │
│                                            (4) Voice commands       │
│                                            & AudioPlayer streams    │
└─────────────────────────────────────────────────────┼───────────────┘
                                                      │
                          ┌───────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     AMAZON CLOUD                                     │
│                                                                      │
│  ┌──────────────────┐    ┌───────────────────────────────────────┐  │
│  │ Alexa Voice      │    │ AWS Lambda / Self-Hosted Skill        │  │
│  │ Service (AVS)    │───▶│ Backend                               │  │
│  │                  │    │                                       │  │
│  │ • Speech → Intent│    │ • Intent handlers                     │  │
│  │ • AudioPlayer    │    │ • Browse: albums, artists, playlists  │  │
│  │ • APL rendering  │    │ • Search: by name/artist/genre        │  │
│  └──────────────────┘    │ • Playback: queue + AudioPlayer.Play  │  │
│                          │ • APL: visual lists for Echo Show     │  │
│                          │ • Token store: OAuth ↔ Jellyfin map   │  │
│                          └──────────────────┬────────────────────┘  │
│                                             │                       │
└─────────────────────────────────────────────┼───────────────────────┘
                                              │
                          (2) Jellyfin REST API calls
                          (3) Audio stream URLs
                                              │
                                              ▼
                          ┌───────────────────────────────────────┐
                          │         JELLYFIN SERVER               │
                          │  (self-hosted, HTTPS, valid SSL)      │
                          │                                       │
                          │  • /Users/AuthenticateByName          │
                          │  • /Users/{id}/Items                  │
                          │  • /Artists/AlbumArtists              │
                          │  • /Audio/{id}/universal (streaming)  │
                          │  • /Items/{id}/Images/Primary         │
                          └───────────────────────────────────────┘
```

### Data Flow

1. **Setup (once):** User opens AnglerAmp → taps "Link to Alexa" → App-to-App OAuth flow → Alexa skill receives and stores an OAuth token mapped to the user's Jellyfin server URL and access token.

2. **Browsing:** User says "Alexa, ask Jelly Player to show my albums" → AVS parses intent → Lambda retrieves Jellyfin token from store → calls `GET /Users/{id}/Items?IncludeItemTypes=MusicAlbum` → returns voice response + optional APL visual list.

3. **Playback:** User says "play Rumours by Fleetwood Mac" → Lambda searches Jellyfin → gets track list → constructs `https://<server>/Audio/{trackId}/universal?api_key=<token>` → sends `AudioPlayer.Play` directive → Alexa streams directly from Jellyfin.

---

## 9. Challenges and Limitations

### 9.1 Hard Requirements

| Requirement | Challenge | Mitigation |
|-------------|-----------|------------|
| **HTTPS with valid SSL** | Jellyfin server must be publicly accessible with a trusted certificate | Use Let's Encrypt, Caddy, or a reverse proxy like nginx. Cloudflare Tunnel is also an option. |
| **Internet-accessible server** | Home servers are typically behind NAT | Use a VPN tunnel service (Cloudflare Tunnel, Tailscale Funnel, ngrok) |
| **Amazon Developer Account** | Required to create and publish a custom skill | Free to create; publishing requires Amazon review |

### 9.2 Technical Challenges

| Challenge | Detail | Severity |
|-----------|--------|----------|
| **Voice browsing is shallow** | Listing hundreds of albums by voice is impractical; users need to search by name or use Echo Show for visual browsing | Medium — mitigated by APL + search intents |
| **Audio URL auth** | Alexa AudioPlayer cannot send custom headers; auth must be in the URL query string | Low — Jellyfin supports `?api_key=` query parameter |
| **Session state** | Multi-turn dialogs ("show albums" → "play the third one") require dialog management | Medium — ASK SDK supports dialog management and session attributes |
| **Transcoding latency** | If Jellyfin needs to transcode a FLAC to MP3, there may be a delay before the stream starts | Low — Jellyfin's transcoding is generally fast; can pre-set codec preferences |
| **Rate limiting** | Rapid browsing could hit Jellyfin's connection limits | Low — unlikely with voice interaction cadence |
| **OAuth server** | Must be built and hosted separately from both AnglerAmp and the skill backend | Medium — can be combined with the skill backend |

### 9.3 UX Limitations vs. AnglerAmp Mobile

| Feature | AnglerAmp (Mobile) | Alexa Skill | Gap |
|---------|-------------------|-------------|-----|
| Browse by folder | ✅ Full hierarchy | ⚠️ Possible but very clunky by voice | Significant |
| Offline playback | ✅ Downloaded tracks | ❌ Not possible | Fundamental — Alexa needs internet |
| Search with keyboard | ✅ Real-time | ⚠️ Voice-only (or Echo Show keyboard) | Moderate |
| Album art display | ✅ Full resolution | ✅ APL on Echo Show | None |
| Queue management | ✅ Drag-and-drop | ⚠️ Voice: "next", "previous", "shuffle" | Moderate |
| Audiobook chapters | ✅ Chapter navigation | ⚠️ Possible but requires custom intents | Moderate |
| Sleep timer | ✅ Built-in | ✅ Alexa native: "Alexa, set a sleep timer" | None |

---

## 10. Verdict

### Is it possible? **Yes.**

### Is it practical? **Yes, with caveats.**

| Aspect | Feasibility | Confidence |
|--------|-------------|------------|
| **Build an Alexa skill that plays Jellyfin audio** | Fully feasible — proven by existing projects | **High** (existing implementations exist) |
| **Mobile-phone pairing via AnglerAmp** | Feasible using App-to-App Account Linking | **High** (Amazon-documented, standard OAuth) |
| **Voice-based library browsing** | Feasible for search + play; limited for deep hierarchy | **Medium** (voice is inherently shallow) |
| **Visual browsing on Echo Show** | Feasible with APL — scrollable album lists with art | **High** (well-documented APL API) |
| **Audiobook browsing** | Feasible — custom intents for audiobook-specific queries | **Medium** (no prior art in existing Alexa-Jellyfin skills) |
| **Folder-based browsing** | Technically possible but poor UX by voice | **Low** (voice navigation of directories is impractical) |

### What Would Need to Be Built

| Component | Effort | Description |
|-----------|--------|-------------|
| **Skill Backend** | Large | Lambda or self-hosted Flask/Node.js app with intent handlers for browse, search, play, queue management |
| **OAuth Server / Token Bridge** | Medium | Maps Alexa OAuth tokens to Jellyfin credentials; handles refresh |
| **Alexa Skill Configuration** | Small | Interaction model (intents, slots, utterances), APL templates, account linking config |
| **AnglerAmp Changes** | Small | "Link to Alexa" button, Universal/App Links support, OAuth flow initiation |
| **APL Templates** | Medium | Visual layouts for album lists, artist lists, now-playing screen (Echo Show only) |

### Recommended Approach

1. **Start with the existing `jellyfin_alexa_skill` project** as a foundation for the backend — it already handles Jellyfin auth, search, and AudioPlayer playback.
2. **Add App-to-App Account Linking** to enable mobile-phone pairing from AnglerAmp.
3. **Add APL templates** for visual browsing on Echo Show devices.
4. **Add custom browse intents** for richer voice navigation (multi-turn dialogs for drill-down).
5. **Defer folder browsing** — it works poorly by voice and adds significant complexity.

---

## 11. References

### Amazon Alexa Documentation
- [Custom Skills Overview](https://developer.amazon.com/en-US/docs/alexa/custom-skills/understanding-custom-skills.html)
- [AudioPlayer Interface Reference](https://developer.amazon.com/en-US/docs/alexa/custom-skills/audioplayer-interface-reference.html)
- [Stream Long-Form Audio](https://developer.amazon.com/en-US/docs/alexa/custom-skills/use-long-form-audio.html)
- [Account Linking Concepts](https://developer.amazon.com/en-US/docs/alexa/account-linking/account-linking-concepts.html)
- [App-to-App Account Linking (from your app)](https://developer.amazon.com/en-US/docs/alexa/account-linking/app-to-app-account-linking-starting-from-your-app.html)
- [App-to-App Account Linking (from Alexa app)](https://developer.amazon.com/en-US/docs/alexa/account-linking/app-to-app-account-linking-starting-from-Alexa-app.html)
- [Set Up App-to-App Account Linking](https://www.developer.amazon.com/en-US/docs/alexa/account-linking/set-up-app-to-app-account-linking.html)
- [APL Interface Reference](https://developer.amazon.com/en-US/docs/alexa/alexa-presentation-language/apl-interface.html)
- [APL Tutorial: First Visual Response](https://developer.amazon.com/en-US/docs/alexa/alexa-presentation-language/tutorial-add-first-visual-response-custom-skill.html)
- [Music Skill API Overview](https://developer.amazon.com/en-US/alexa/alexa-skills-kit/get-deeper/music-skills)
- [Host a Custom Skill as a Web Service](https://developer.amazon.com/en-US/docs/alexa/custom-skills/host-a-custom-skill-as-a-web-service.html)
- [Alexa for Apps](https://developer.amazon.com/en-US/docs/alexa/alexa-for-apps/about-alexa-for-apps.html)

### Jellyfin API Documentation
- [Jellyfin API Authorization](https://gist.github.com/nielsvanvelzen/ea047d9028f676185832e51ffaf12a6f)
- [Jellyfin API Overview (James Harvey)](https://jmshrv.com/posts/jellyfin-api/)
- [Jellyfin Kotlin SDK — Authentication](https://kotlin-sdk.jellyfin.org/guide/authentication.html)
- [UniversalAudioApi Reference](https://webysther.github.io/jellyfin-sdk-python.github.io/api_10_11/docs/UniversalAudioApi/)

### Existing Jellyfin–Alexa Projects
- [infinityofspace/jellyfin_alexa_skill](https://github.com/infinityofspace/jellyfin_alexa_skill) — Python/Flask self-hosted Alexa skill
- [Rusketh/JellyMusic](https://github.com/Rusketh/JellyMusic) — Docker-based Alexa skill for Jellyfin
- [infinityofspace/jellyfin-alexa-plugin](https://github.com/infinityofspace/jellyfin-alexa-plugin) — Jellyfin server plugin
- [jellyfin-alexa-skill on PyPI](https://pypi.org/project/jellyfin-alexa-skill/)

### AnglerAmp / Finamp Codebase (this repository)
- `lib/services/jellyfin_api.dart` — Chopper REST client definition (450 lines)
- `lib/services/jellyfin_api_helper.dart` — API helper with browse/play logic (607 lines)
- `lib/services/carplay_service.dart` — CarPlay bridge (219 lines) — closest architectural analogy
- `lib/services/music_player_background_task.dart` — Audio playback service (807 lines)
- `lib/models/finamp_models.dart` — FinampUser, FinampSettings, TabContentType
- `lib/models/jellyfin_models.dart` — BaseItemDto, AuthenticationResult, and 100+ API models

### Other Resources
- [Alexa Skill Sample for AudioPlayer (Node.js)](https://github.com/alexa-samples/skill-sample-nodejs-audio-player)
- [Alexa Skill Sample for AudioPlayer (Python)](https://github.com/alexa-samples/skill-sample-python-audio-player)
- [Alexa for Apps Skill Sample](https://github.com/alexa-labs/skill-sample-alexa-for-apps)
- [Self-hosted Alexa local skills (nitzzzu)](https://github.com/nitzzzu/alexa-local-skills)
- [Alexa OAuth Sample Server](https://github.com/alexa-samples/alexa-oauth-sample)
