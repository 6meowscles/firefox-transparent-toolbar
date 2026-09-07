/* Firefox Wallpaper Underlay
 *
 * A transparent window is transparent to whatever is *directly below it in the
 * stacking order* -- usually another window, not the desktop. Nothing in CSS
 * can reach past that; the compositor composites in Z order and there is no
 * "show me the wallpaper specifically" mode.
 *
 * So instead of asking Firefox to see further down, this puts the wallpaper
 * further up: a Meta.BackgroundActor is inserted into global.window_group
 * immediately below the Firefox window actor, clipped to the window's frame
 * rect. Firefox's see-through pixels then composite over wallpaper, and the
 * windows in between are masked out for exactly the region Firefox covers.
 *
 * Because the actor is anchored to the monitor rather than to the window, it
 * stays pixel-aligned with the real desktop for free -- move or unmaximize the
 * window and the image behind it doesn't slide, which is the limitation the
 * userChrome.css wallpaper mode can't escape.
 */

import Meta from 'gi://Meta';

import * as Background from 'resource:///org/gnome/shell/ui/background.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

/* Matched against the window's WM_CLASS, lowercased. */
const WM_CLASS_RE = /^(firefox|librewolf|waterfox|floorp)/;

/** The wallpaper patch for one browser window. */
class Underlay {
    constructor(window) {
        this._window = window;
        this._windowActor = null;
        this._manager = null;
        this._managerChangedId = 0;
        this._monitorIndex = -1;
        this._actorSignals = [];

        this._windowSignals = [
            window.connect('position-changed', () => this.sync()),
            window.connect('size-changed', () => this.sync()),
            window.connect('workspace-changed', () => this.sync()),
            window.connect('notify::minimized', () => this.sync()),
            window.connect('notify::monitor', () => this.sync()),
        ];

        this.sync();
    }

    /* The manager owns the actor and swaps in a new one when the wallpaper
       changes, so it is rebuilt only when the window changes monitor. */
    _ensureManager(monitorIndex) {
        if (this._manager && this._monitorIndex === monitorIndex)
            return;

        this._destroyManager();
        this._monitorIndex = monitorIndex;
        this._manager = new Background.BackgroundManager({
            container: global.window_group,
            monitorIndex,
            controlPosition: true,   // positions the actor at the monitor origin
            useContentSize: true,
        });
        /* 'changed' fires when a new actor has been swapped in after a
           wallpaper change; it arrives unclipped and at the bottom. */
        this._managerChangedId = this._manager.connect('changed', () => this.sync());
    }

    _destroyManager() {
        if (this._managerChangedId) {
            this._manager.disconnect(this._managerChangedId);
            this._managerChangedId = 0;
        }
        this._manager?.destroy();
        this._manager = null;
        this._monitorIndex = -1;
    }

    _trackWindowActor(windowActor) {
        if (windowActor === this._windowActor)
            return;

        for (const id of this._actorSignals)
            this._windowActor.disconnect(id);
        this._actorSignals = [];
        this._windowActor = windowActor;

        if (windowActor) {
            this._actorSignals = [
                windowActor.connect('notify::visible', () => this.sync()),
                windowActor.connect('notify::mapped', () => this.sync()),
            ];
        }
    }

    /** Re-place, re-clip and re-show the patch for where the window is now. */
    sync() {
        const window = this._window;
        const windowActor = window.get_compositor_private();
        const monitorIndex = window.get_monitor();
        const monitor = Main.layoutManager.monitors[monitorIndex];

        this._trackWindowActor(windowActor);

        /* No actor yet (window-created fires first), or the monitor went away. */
        if (!windowActor || !monitor) {
            this._destroyManager();
            return;
        }

        this._ensureManager(monitorIndex);
        const background = this._manager.backgroundActor;
        if (!background)
            return;

        /* Clip is in the actor's own coordinates, and the actor sits at the
           monitor origin -- so this is the window rect made monitor-relative. */
        const rect = window.get_frame_rect();
        background.set_clip(
            rect.x - monitor.x, rect.y - monitor.y, rect.width, rect.height);

        background.visible = windowActor.visible && !window.minimized;

        /* Mutter re-sorts window_group on every restack and leaves our actor
           wherever it lands, so the stacking has to be re-asserted. During a
           workspace-switch animation the window actor is reparented out of
           window_group; skip rather than restack across parents. */
        if (windowActor.get_parent() === background.get_parent())
            global.window_group.set_child_below_sibling(background, windowActor);
    }

    destroy() {
        for (const id of this._windowSignals)
            this._window.disconnect(id);
        this._windowSignals = [];
        this._trackWindowActor(null);
        this._destroyManager();
    }
}

export default class FirefoxWallpaperUnderlayExtension extends Extension {
    enable() {
        this._underlays = new Map();
        this._watched = new Map();

        this._displayIds = [
            global.display.connect('window-created', (_display, window) => this._watch(window)),
            global.display.connect('restacked', () => this._syncAll()),
        ];
        this._workspaceId =
            global.workspace_manager.connect('active-workspace-changed', () => this._syncAll());

        for (const windowActor of global.get_window_actors())
            this._watch(windowActor.meta_window);
    }

    disable() {
        for (const id of this._displayIds)
            global.display.disconnect(id);
        this._displayIds = [];
        global.workspace_manager.disconnect(this._workspaceId);
        this._workspaceId = 0;

        for (const window of [...this._watched.keys()])
            this._forget(window);
    }

    /* A window is watched from the moment it appears, but not necessarily
       matched: on Wayland the app id (and on X11 the WM_CLASS) arrives in a
       later roundtrip, so at 'window-created' get_wm_class() is still null and
       deciding once here would never match anything. */
    _watch(window) {
        if (!window || this._watched.has(window) ||
            window.window_type !== Meta.WindowType.NORMAL)
            return;

        this._watched.set(window, [
            window.connect('unmanaged', () => this._forget(window)),
            window.connect('notify::wm-class', () => this._evaluate(window)),
        ]);
        this._evaluate(window);
    }

    _evaluate(window) {
        const wmClass = window.get_wm_class()?.toLowerCase();
        const wanted = !!wmClass && WM_CLASS_RE.test(wmClass);
        const underlay = this._underlays.get(window);

        if (wanted && !underlay) {
            this._underlays.set(window, new Underlay(window));
        } else if (!wanted && underlay) {
            underlay.destroy();
            this._underlays.delete(window);
        }
    }

    _forget(window) {
        for (const id of this._watched.get(window) ?? [])
            window.disconnect(id);
        this._watched.delete(window);

        this._underlays.get(window)?.destroy();
        this._underlays.delete(window);
    }

    _syncAll() {
        for (const underlay of this._underlays.values())
            underlay.sync();
    }
}
