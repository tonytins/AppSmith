import Gio from 'gi://Gio';
import Nautilus from 'gi://Nautilus';
import GObject from 'gi://GObject';

export class AppBundleExtension extends GObject.Object {
    constructor() {
        super();
    }

    get_file_items(window, files) {
        // Only show menu for .app bundles
        if (files.length !== 1) {
            return [];
        }

        const file = files[0];
        const uri = file.get_uri();
        if (!uri.endsWith('.app')) {
            return [];
        }

        // Verify it's a directory with your structure
        const path = file.get_location().get_path();
        const iconDir = `${path}/Contents/Resources`;
        const iconDirFile = Gio.File.new_for_path(iconDir);

        try {
            if (iconDirFile.query_file_type(Gio.FileQueryInfoFlags.NONE, null) !== Gio.FileType.DIRECTORY) {
                return [];
            }
        } catch (e) {
            return [];
        }

        // Create menu item
        const item = new Nautilus.MenuItem({
            name: 'AppBundleOpen',
            label: 'Open App Bundle',
            tip: 'Launch this app bundle'
        });

        item.connect('activate', () => this._openBundle(path));
        return [item];
    }

    _openBundle(path) {
        try {
            const launcher = new Gio.SubprocessLauncher({
                flags: Gio.SubprocessFlags.NONE
            });
            launcher.spawn(['dotappimage', 'open', path]);
        } catch (e) {
            console.error(`Failed to launch: ${e.message}`);
        }
    }
}
