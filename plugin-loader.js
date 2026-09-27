/*
 * plugin-loader.js — custom addition to the Jellyfin Tizen app.
 *
 * Jellyfin web plugins (Jellyfin Enhanced, Media Bar, All Users Recently Watched, ...)
 * are injected by the server's File Transformation plugin into the index.html it serves.
 * This app ships its own copy of jellyfin-web, so those injections never reach it.
 *
 * After sign-in, this loader fetches <server>/web/index.html, finds the tags the server
 * added (the ones pointing at "../<Plugin>/..."), and loads them from the server.
 * Scripts that assume they run on the server's own origin get two narrow patches:
 *   - window.location.origin          -> the server address
 *   - includes/endsWith("/web/...")   -> "/www/..." (this app's page path)
 *
 * To skip a plugin on this TV, set localStorage "pluginLoaderDisabled" to a comma
 * list of path fragments, e.g. "MediaBar,JellyfinEnhanced".
 */
(function () {
    'use strict';

    var TAG = '[plugin-loader]';
    var POLL_MS = 1000;

    function log() {
        try { console.log.apply(console, [TAG].concat([].slice.call(arguments))); } catch (e) { /* ignore */ }
    }

    function signedIn() {
        var c = window.ApiClient;
        return c && typeof c.serverAddress === 'function' && c.serverAddress()
            && typeof c.accessToken === 'function' && c.accessToken();
    }

    function waitForSignIn() {
        return new Promise(function (resolve) {
            (function poll() {
                if (signedIn()) resolve(window.ApiClient);
                else setTimeout(poll, POLL_MS);
            })();
        });
    }

    function absolute(base, url) {
        return base + '/' + url.replace(/^(\.\.\/)+/, '').replace(/^\/+/, '');
    }

    function needsPatch(text) {
        return /window\.location\.origin/.test(text)
            || /(includes|endsWith|startsWith)\((["'`])\/web\//.test(text);
    }

    function patch(text, base) {
        return text
            .replace(/window\.location\.origin/g, JSON.stringify(base))
            .replace(/(includes|endsWith|startsWith)\((["'`])\/web\//g, '$1($2/www/');
    }

    function disabledList() {
        try {
            return (localStorage.getItem('pluginLoaderDisabled') || '')
                .toLowerCase().split(',')
                .map(function (s) { return s.trim(); })
                .filter(Boolean);
        } catch (e) {
            return [];
        }
    }

    function copyAttributes(from, to) {
        for (var i = 0; i < from.attributes.length; i++) {
            var a = from.attributes[i];
            if (a.name === 'src' || a.name === 'defer' || a.name === 'async') continue;
            to.setAttribute(a.name, a.value);
        }
    }

    function loadScriptSrc(el) {
        return new Promise(function (resolve) {
            el.onload = resolve;
            el.onerror = function () { log('failed to load', el.src); resolve(); };
            document.head.appendChild(el);
        });
    }

    function loadInjected(base) {
        return fetch(base + '/web/index.html', { cache: 'no-store' })
            .then(function (r) { return r.text(); })
            .then(function (html) {
                var doc = new DOMParser().parseFromString(html, 'text/html');
                var skip = disabledList();
                var nodes = [].slice.call(doc.querySelectorAll('script[src], link[rel="stylesheet"][href]'));

                // Only tags the server injected: they point one level up ("../Plugin/...").
                // The stock web client's own files are same-directory and already bundled here.
                nodes = nodes.filter(function (n) {
                    var u = n.getAttribute('src') || n.getAttribute('href') || '';
                    if (!/^\.\.\//.test(u)) return false;
                    var lower = u.toLowerCase();
                    if (skip.some(function (s) { return lower.indexOf(s) !== -1; })) {
                        log('skipped (disabled):', u);
                        return false;
                    }
                    return true;
                });

                log('found', nodes.length, 'server-injected tag(s)');

                return nodes.reduce(function (chain, n) {
                    return chain.then(function () {
                        if (n.tagName === 'LINK') {
                            var link = document.createElement('link');
                            link.rel = 'stylesheet';
                            link.href = absolute(base, n.getAttribute('href'));
                            document.head.appendChild(link);
                            log('css', link.href);
                            return;
                        }

                        var url = absolute(base, n.getAttribute('src'));
                        return fetch(url, { cache: 'no-store' })
                            .then(function (r) { return r.text(); })
                            .then(function (text) {
                                var el = document.createElement('script');
                                copyAttributes(n, el);
                                if (needsPatch(text)) {
                                    el.textContent = patch(text, base) + '\n//# sourceURL=' + url;
                                    document.head.appendChild(el);
                                    log('js (patched)', url);
                                    return;
                                }
                                el.src = url;
                                log('js', url);
                                return loadScriptSrc(el);
                            });
                    }).catch(function (e) {
                        log('error loading', n.outerHTML, e && e.message);
                    });
                }, Promise.resolve());
            });
    }

    waitForSignIn()
        .then(function (api) {
            var base = api.serverAddress().replace(/\/+$/, '');
            log('signed in to', base);
            return loadInjected(base);
        })
        .catch(function (e) { log('loader failed:', e && e.message); });
})();
