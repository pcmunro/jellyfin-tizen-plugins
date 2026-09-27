# jellyfin-tizen-plugins

A Jellyfin app for Samsung (Tizen) TVs that also loads the **web plugins installed on your Jellyfin server**, such as Jellyfin Enhanced, Media Bar and All Users Recently Watched.

It starts from the prebuilt [jellyfin-tizen-builds](https://github.com/jeppevinkel/jellyfin-tizen-builds) package and adds one file, `plugin-loader.js`.

## Why this is needed

Plugins like Jellyfin Enhanced and Media Bar don't change Jellyfin itself. The server's **File Transformation** plugin adds their `<script>`/`<link>` tags to the `index.html` it serves at `/web/`.

The Tizen app ships its **own bundled copy** of jellyfin-web and never loads the server's `index.html`, so those plugins never appear on the TV.

## How it works

`plugin-loader.js` runs inside the bundled web client:

1. It waits until you're signed in, when `ApiClient` has a server address and an access token.
2. It fetches `<server>/web/index.html` and collects the tags the server injected. Those are the ones pointing one level up (`../MediaBar/...`, `../JellyfinEnhanced/...`). The web client's own files are bundled, so they're skipped.
3. It loads each one from the server, copying the original tag's attributes. Jellyfin Enhanced, for example, reads its `plugin`/`version` attributes.
4. Scripts written to run on the server's own address get two narrow patches before running:
   - `window.location.origin` is replaced with the server address.
   - `includes/endsWith/startsWith("/web/…")` checks become `"/www/…"`, the path of this app's page. Media Bar uses these to detect the home page.

Anything you add or update on the server later is picked up automatically, with no rebuild. The server must allow cross-origin requests; Jellyfin sends `Access-Control-Allow-Origin: *` by default.

## Build

Windows PowerShell 5.1 or later. No Node.js or Tizen Studio needed.

```powershell
.\build.ps1 -Release latest -Version 0.1.2
```

| Parameter | Default | Notes |
|---|---|---|
| `-Release` | `latest` | A jellyfin-tizen-builds release tag, e.g. `2026-09-27-1820` |
| `-Variant` | `Jellyfin` | Asset name without `.wgt`. `Jellyfin` = web client matching the current stable server; the release notes list the others (`10.11.z`, `master`, …). |
| `-Version` | `0.1.1` | Written to `config.xml`. Must be higher than the installed version to install as an update. |

The output goes to `dist\Jellyfin-Frame-plugins-<version>.wgt`. It's **unsigned**: the original signatures are removed because the files changed.

Pick a variant whose jellyfin-web matches your server version. A web client older than the server (for example 10.10 against a 12.x server) uses legacy login methods and gets logged out unless the server has `EnableLegacyAuthorization` turned on.

## Install

1. On the TV: **Apps → 1 2 3 4 5 → Developer mode ON**, with host IP set to your PC's LAN address. Then fully restart the TV by holding the power button.
2. In [Apps2Samsung](https://github.com/Apps2Samsung/Apps2Samsung), choose **custom WGT**, select the built `.wgt`, pick the TV and click **Install**. Apps2Samsung signs it with your TV's certificate.
3. It keeps the stock app ID (`AprZAARz4r.Jellyfin`), so it replaces the stock Jellyfin app and you stay signed in.

Don't reinstall the stock Jellyfin build over it, or the plugins disappear.

If Apps2Samsung reports *"TV Name could not be found"*, check that your PC reaches the TV over the LAN and not through a VPN. With Tailscale, turn off "Use Tailscale subnets" (`tailscale set --accept-routes=false`) while at home.

## Turning a plugin off on one TV

The loader skips any injected file whose path contains one of the names in the `pluginLoaderDisabled` localStorage key (a comma-separated list). Set it from the app's web inspector (Apps2Samsung's 🐞 debug button):

```js
localStorage.setItem('pluginLoaderDisabled', 'MediaBar');   // then restart the app
localStorage.removeItem('pluginLoaderDisabled');            // re-enable all
```

Loader messages appear in the inspector console prefixed with `[plugin-loader]`.

## Tested

| | |
|---|---|
| TV | Samsung The Frame 2025 (QN65LS03FAFXZC, Tizen 9) |
| Server | Jellyfin 12.1.0 |
| Base build | jellyfin-tizen-builds `2026-09-27-1820`, `Jellyfin.wgt` (jellyfin-web v12.1) |
| Plugins | Jellyfin Enhanced 12.9, Media Bar 3.0, All Users Recently Watched 1.0 (via File Transformation 3.0.1) |

## License

`plugin-loader.js` and `build.ps1` are released under the **Mozilla Public License 2.0** (see `LICENSE`), the same license as [jellyfin-tizen](https://github.com/jellyfin/jellyfin-tizen).

The built package also contains [jellyfin-web](https://github.com/jellyfin/jellyfin-web), which is **GPL-2.0**. Its source is available from that project.
