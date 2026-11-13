pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services

/**
 * The Books library: the keybind, the IPC target and the window, built only while open.
 */
Scope {
    id: root

    function requestOpen(): void {
        GlobalStates.booksOverlayOpen = false;
        GlobalStates.openBooksApp();
    }

    function requestClose(): void {
        GlobalStates.booksOpen = false;
    }

    function requestOverlay(): void {
        GlobalStates.booksOpen = false;
        GlobalStates.booksOverlayOpen = !GlobalStates.booksOverlayOpen;
    }

    function requestToggle(): void {
        if (GlobalStates.booksOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    Loader {
        active: GlobalStates.booksOpen
        sourceComponent: BooksWindow {
            onCloseRequested: root.requestClose()
        }
    }

    Loader {
        active: GlobalStates.booksOverlayOpen
        sourceComponent: BooksOverlay {
            onCloseRequested: GlobalStates.booksOverlayOpen = false
        }
    }

    GlobalShortcut {
        name: "booksOverlayToggle"
        description: "Toggles the immersive Books overlay"
        onPressed: root.requestOverlay()
    }

    GlobalShortcut {
        name: "booksToggle"
        description: "Toggles the Books library"
        onPressed: root.requestToggle()
    }

    IpcHandler {
        target: "books"

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }

        /// The full-screen, scroll-and-type browser.
        function overlay(): void {
            root.requestOverlay();
        }

        function refresh(): void {
            BooksService.refresh();
        }

        function manga(): void {
            root.requestOpen();
            BooksService.openSource("manga");
        }

        function source(id: string): void {
            root.requestOpen();
            BooksService.openSource(id);
        }

        function browse(url: string): void {
            root.requestOpen();
            if (BooksService.sourceId !== "manga")
                BooksService.openSource("manga");
            BooksService.browseOpen(url);
        }

        function download(url: string): void {
            root.requestOpen();
            BooksService.download({ "title": "Manga", "author": "" }, {
                "href": url,
                "ext": "cbz",
                "size": 0,
                "label": "chapter"
            });
        }
    }
}
