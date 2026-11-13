import qs  
import qs.services  
import qs.modules.common  
import qs.modules.common.widgets  
import qs.modules.common.functions  
import qs.modules.ii.sidebarPolicies.wallpaperBrowser  
import QtQuick  
import QtQuick.Controls  
import QtQuick.Layouts  
import Qt5Compat.GraphicalEffects  
import Quickshell  
  
Item {  
    id: root  
    property real padding: 4  
    property var inputField: searchInputField  
    property string commandPrefix: "/"  
    property string currentService: WallpaperBrowser.currentProvider ?? "unsplash"  
    property var suggestionQuery: ""  
    property var suggestionList: []  
    property int imageLimit: 20
      
    // Exact same pattern as Anime  
    readonly property var responses: WallpaperBrowser.responses  
    property int lastResponseLength: 0  
      
    // Download paths  
    property string downloadPath: Config.options.wallpapers.paths.download 
    property string nsfwPath: Config.options.wallpapers.paths.nsfw // not sure if needed
      
    // Pagination properties  
    property real scrollOnNewResponse: 100  
    property real pullLoadingGap: 100  
    property bool pullLoading: false  
    property real normalizedPullDistance: 0  

    // Input field properties  
    property bool containsDrag: false  
    property string previewPath: ""
      
    // Entrance Animations Trigger
    property int entranceTrigger: -1
    function triggerContentEntrance() {
        root.entranceTrigger++;
    }

    onEntranceTriggerChanged: {
        if (entranceTrigger >= 0) {
            columnLayout.opacity = 0
            columnLayoutTrans.y = 25
            columnLayout.scale = 0.96

            searchInputContainer.opacity = 0
            searchInputContainerTrans.y = 15
            searchInputContainer.scale = 0.95

            Qt.callLater(function() {
                wallpaperEntranceAnim.stop()
                wallpaperEntranceAnim.start()
            })
        }
    }

    ParallelAnimation {
        id: wallpaperEntranceAnim

        SequentialAnimation {
            PauseAnimation { duration: Appearance.dur(60) }
            ParallelAnimation {
                NumberAnimation { target: columnLayout; property: "opacity"; to: 1.0; duration: Appearance.dur(350); easing.type: Easing.OutCubic }
                NumberAnimation { target: columnLayoutTrans; property: "y"; to: 0; duration: Appearance.dur(400); easing.type: Easing.OutBack; easing.overshoot: 1.15 }
                NumberAnimation { target: columnLayout; property: "scale"; to: 1.0; duration: Appearance.dur(400); easing.type: Easing.OutBack; easing.overshoot: 1.15 }
            }
        }

        SequentialAnimation {
            PauseAnimation { duration: Appearance.dur(180) }
            ParallelAnimation {
                NumberAnimation { target: searchInputContainer; property: "opacity"; to: 1.0; duration: Appearance.dur(320); easing.type: Easing.OutCubic }
                NumberAnimation { target: searchInputContainerTrans; property: "y"; to: 0; duration: Appearance.dur(380); easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                NumberAnimation { target: searchInputContainer; property: "scale"; to: 1.0; duration: Appearance.dur(380); easing.type: Easing.OutBack; easing.overshoot: 1.2 }
            }
        }
    }

    onFocusChanged: focus => {  
        if (focus) {  
            root.inputField.forceActiveFocus();  
        }  
    }  

      
    ColumnLayout {  
        id: columnLayout
        anchors.fill: parent  
        anchors.margins: 4
        spacing: 10  

        transform: Translate {
            id: columnLayoutTrans
            y: 0
        }
          
        Item {  
            Layout.fillWidth: true  
            Layout.fillHeight: true  
              
            layer.enabled: true  
            layer.effect: OpacityMask {  
                maskSource: Rectangle {  
                    width: columnLayout.width  
                    height: columnLayout.height  
                    radius: Appearance.rounding.small  
                }  
            }
              
            ScrollEdgeFade {  
                z: 1  
                target: responseListView  
                vertical: true  
            }  
              
            StyledListView {  
                id: responseListView  
                anchors.fill: parent
                visible: root.responses.length > 0 

                function nextPage() {
                    root.pullLoading = true  
                    root.handleInput(`${root.commandPrefix}next`)
                }

                property var modelValues: root.responses
                onModelValuesChanged: responseListView.positionViewAtEnd()
                
                model: ScriptModel {  
                    values: root.responses
                }  
                delegate: WallpaperResponse {  
                    responseData: modelData  
                    tagInputField: root.inputField  
                    downloadPath: root.downloadPath  
                    nsfwPath: root.nsfwPath  
                } 

                onDragEnded: {  // pulling to go to next page
                    const gap = responseListView.verticalOvershoot  
                    if (gap > root.pullLoadingGap) {  
                        responseListView.nextPage()
                    }  
                }  
            }  

            PagePlaceholder {  
                id: placeholderItem  
                shown: root.responses.length === 0  
                icon: "wallpaper"
                description: Translation.tr("Type %1service to get started").arg(root.commandPrefix)  
                title: Translation.tr("Wallpapers (beta)")  
                shape: MaterialShape.Shape.Cookie9Sided  
            } 
              
            ScrollToBottomButton {  
                z: 3  
                target: responseListView  
            }  
              
            MaterialLoadingIndicator {
                visible: WallpaperBrowser.runningRequests > 0
                id: loadingIndicator  
                z: 4  
                anchors {  
                    horizontalCenter: parent.horizontalCenter  
                    bottom: parent.bottom  
                    bottomMargin: 20 + (root.pullLoading ? 0 : Math.max(0, (root.normalizedPullDistance - 0.5) * 50))  
                }  
                loading: WallpaperBrowser.runningRequests > 0  
            }  
        }  
          
        DescriptionBox {  
            text: root.suggestionList[suggestions.selectedIndex]?.description ?? ""  
            showArrows: root.suggestionList.length > 1  
        }  
          
        FlowButtonGroup {  
            id: suggestions  
            visible: root.suggestionList.length > 0 && searchInputField.text.length > 0  
            property int selectedIndex: 0  
            Layout.fillWidth: true  
            spacing: 5  
              
            Repeater {  
                id: suggestionRepeater  
                model: {  
                    suggestions.selectedIndex = 0;  
                    return root.suggestionList.slice(0, 10);  
                }  
                delegate: ApiCommandButton {  
                    id: commandButton  
                    colBackground: suggestions.selectedIndex === index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer  
                    bounce: false  
                    contentItem: StyledText {  
                        font.pixelSize: Appearance.font.pixelSize.small  
                        color: Appearance.m3colors.m3onSurface  
                        horizontalAlignment: Text.AlignHCenter  
                        text: modelData.displayName ?? modelData.name  
                    }  
                    onHoveredChanged: {  
                        if (commandButton.hovered) {  
                            suggestions.selectedIndex = index;  
                        }  
                    }  
                    onClicked: {  
                        suggestions.acceptSuggestion(modelData.name);  
                    }  
                }  
            }  
              
            function acceptSuggestion(word) {  
                const words = searchInputField.text.trim().split(/\s+/);  
                if (words.length > 0) {  
                    words[words.length - 1] = word;  
                } else {  
                    words.push(word);  
                }  
                const updatedText = words.join(" ") + " ";  
                searchInputField.text = updatedText;  
                searchInputField.cursorPosition = searchInputField.text.length;  
                searchInputField.forceActiveFocus();  
            }  
              
            function acceptSelectedWord() {  
                if (suggestions.selectedIndex >= 0 && suggestions.selectedIndex < suggestionRepeater.count) {  
                    const word = root.suggestionList[suggestions.selectedIndex].name;  
                    suggestions.acceptSuggestion(word);  
                }  
            }  
        }  

        AttachedFileIndicator {
            visible: implicitHeight > 0
            implicitHeight: root.containsDrag ? contentHeight : 0
            opacity: root.containsDrag ? 1 : 0
            highlight: false

            Layout.fillWidth: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            filePath: root.previewPath
            
        }
          
        Rectangle {  
            id: searchInputContainer  
            property real spacing: 5  
            Layout.fillWidth: true  
            radius: Appearance.rounding.normal - root.padding  
            color: Appearance.colors.colLayer2  
            implicitHeight: Math.max(inputFieldRowLayout.implicitHeight + inputFieldRowLayout.anchors.topMargin + statusRowLayout.implicitHeight + statusRowLayout.anchors.bottomMargin + spacing, 45)  
            clip: true  
              
            transform: Translate {
                id: searchInputContainerTrans
                y: 0
            }

            Behavior on scale { NumberAnimation { duration: Appearance.dur(200); easing.type: Easing.OutCubic } }


            DropArea {
                id: dropArea
                anchors.fill: parent

                readonly property string currentProvider: WallpaperBrowser.currentProvider
                function getWallhavenId(url) {
                    const urlStr = url.toString()
                    const fileName = urlStr.split('/').pop() 
                    const fileNameWithoutExt = fileName.split('.')[0] 
                    const match = fileNameWithoutExt.match(/^wallhaven-([a-zA-Z0-9]{6})$/i)
                    return match ? match[1] : null
                }

                onContainsDragChanged: root.containsDrag = dropArea.containsDrag

                onEntered: (drag) => {
                    if (currentProvider !== "wallhaven") return
                    if (!Images.isValidImageByName(drag.urls[0])) return
                    if (drag.hasUrls && drag.urls.length > 0) {
                        root.previewPath = drag.urls[0]
                    }
                }
                onExited: root.previewPath = ""

                onDropped: (drop) => {
                    if (drop.hasUrls) {
                        for (var i = 0; i < drop.urls.length; i++) {
                            const fileUrl = drop.urls[i]

                            const wallhavenId = getWallhavenId(fileUrl)
                            if (currentProvider !== "wallhaven") {
                                WallpaperBrowser.addSystemMessage(Translation.tr("Similar images only works with wallhaven service"));  
                                continue
                            }
                            if (!Images.isValidImageByName(fileUrl)) {
                                WallpaperBrowser.addSystemMessage(Translation.tr("Please drop an image file"));  
                                continue
                            }
                            if (!wallhavenId) {
                                WallpaperBrowser.addSystemMessage(Translation.tr("Please drop a valid wallhaven image named like **wallhaven-######.png**"));  
                                continue
                            }

                            console.log("[Wallpaper Browser] Dropped image:", fileUrl)
                            WallpaperBrowser.addSimilarImageMessage(Translation.tr("Searching for a similar image:"), fileUrl)
                            root.handleInput(root.commandPrefix + "similar " + wallhavenId);
                        }
                        drop.accept(Qt.CopyAction)
                    }
                }
            }

            RowLayout {  
                id: inputFieldRowLayout  
                anchors.left: parent.left  
                anchors.right: parent.right  
                anchors.top: parent.top  
                anchors.margins: 10  
                spacing: 10  
                  
                StyledTextArea {  
                    id: searchInputField  
                    Layout.fillWidth: true  
                    Layout.fillHeight: true  
                    placeholderText: WallpaperBrowser.currentProvider === "wallhaven" ? Translation.tr("Search or drag wallpapers...") : Translation.tr("Search wallpapers... (e.g., nature, abstract)")  
                      
                    onTextChanged: {  
                        if (searchInputField.text.length === 0) {  
                            root.suggestionQuery = "";  
                            root.suggestionList = [];  
                            return;  
                        } else if (searchInputField.text.startsWith(`${root.commandPrefix}service`)) {  
                            root.suggestionQuery = searchInputField.text.split(" ").slice(1).join(" ");  
                            root.suggestionList = [  
                                { name: `${root.commandPrefix}service unsplash`, description: Translation.tr("Use Unsplash (requires API key)") },  
                                { name: `${root.commandPrefix}service wallhaven`, description: Translation.tr("Use Wallhaven (API key optional)") }  
                            ];  
                        } else if (searchInputField.text.startsWith(`${root.commandPrefix}sort`)) {  
                            // Options for wallhaven: date_added, relevance, random, views, favorites, toplist, hot // Options for unsplash: relevant, latest
                            root.suggestionQuery = searchInputField.text.split(" ").slice(1).join(" "); 
                            const currentService = root.currentService 
                            if (currentService === "wallhaven") {
                                root.suggestionList = [  
                                    { name: `${root.commandPrefix}sort date_added`, description: "" },  
                                    { name: `${root.commandPrefix}sort relevance `, description: "" },
                                    { name: `${root.commandPrefix}sort random`, description: "" },
                                    { name: `${root.commandPrefix}sort views`, description: "" },
                                    { name: `${root.commandPrefix}sort favorites`, description: "" },
                                    { name: `${root.commandPrefix}sort hot`, description: "" },
                                    { name: `${root.commandPrefix}sort toplist`, description: "" }  
                                ]; 
                            }
                            if (currentService === "unsplash") {
                                root.suggestionList = [  
                                    { name: `${root.commandPrefix}sort relevant`, description: "" },  
                                    { name: `${root.commandPrefix}sort latest`, description: "" }  
                                ]; 
                            }
                             
                        } else if (searchInputField.text.startsWith(`${root.commandPrefix}api`)) {  
                            root.suggestionQuery = searchInputField.text.split(" ").slice(1).join(" ");  
                            if (root.currentService === "wallhaven") {  
                                root.suggestionList = [  
                                    { name: `${root.commandPrefix}api YOUR_KEY`, description: Translation.tr("Optional Wallhaven key, unlocks NSFW (api clear removes it)") }  
                                ];  
                            } else {  
                                root.suggestionList = [  
                                    { name: `${root.commandPrefix}api YOUR_KEY`, description: Translation.tr("Set your Unsplash API key") }  
                                ];  
                            } 
                        } else if (searchInputField.text.startsWith(`${root.commandPrefix}anime`)) {  
                            root.suggestionList = [  
                                { name: `${root.commandPrefix}anime show`, description: Translation.tr("Shows anime-related results") },  
                                { name: `${root.commandPrefix}anime hide`, description: Translation.tr("Hides anime-related results") }  
                            ];   
                        } else if (searchInputField.text.startsWith(root.commandPrefix)) {  
                            root.suggestionQuery = searchInputField.text;  
                            root.suggestionList = root.allCommands.filter(cmd => cmd.name.startsWith(searchInputField.text.substring(1))).map(cmd => {  
                                return { name: `${root.commandPrefix}${cmd.name}`, description: `${cmd.description}` };  
                            });  
                        }  
                    }  
                      
                    Keys.onPressed: event => {  
                        if (event.key === Qt.Key_Return && event.modifiers & Qt.ShiftModifier) {  
                            searchInputField.insert(searchInputField.cursorPosition, "\n");  
                        } else if (event.key === Qt.Key_Return) {  
                            const inputText = searchInputField.text;  
                            searchInputField.clear();  
                            root.handleInput(inputText);  
                            event.accepted = true;  
                        } else if (event.key === Qt.Key_Tab) {  
                            if (root.suggestionList.length > 0) {  
                                const selected = root.suggestionList[suggestions.selectedIndex];  
                                searchInputField.text = selected.name + " ";  
                                searchInputField.cursorPosition = searchInputField.text.length;  
                                searchInputField.forceActiveFocus();  
                            }  
                            event.accepted = true;  
                        } else if (event.key === Qt.Key_Up) {  
                            if (suggestions.selectedIndex > 0) {  
                                suggestions.selectedIndex--;  
                            }  
                            event.accepted = true;  
                        } else if (event.key === Qt.Key_Down) {  
                            if (suggestions.selectedIndex < root.suggestionList.length - 1) {  
                                suggestions.selectedIndex++;  
                            }  
                            event.accepted = true;  
                        }  
                    }  
                }  
                  
                RippleButton {  
                    id: searchButton  
                    Layout.preferredWidth: 40  
                    Layout.preferredHeight: 40  
                    enabled: searchInputField.text.trim().length > 0  

                    colBackground: enabled ? Appearance.colors.colPrimary : "transparent"
                    colBackgroundHover: enabled ? Appearance.colors.colPrimaryHover : "transparent"
                       
                    onClicked: {  
                        const inputText = searchInputField.text;  
                        searchInputField.clear();  
                        root.handleInput(inputText);  
                    }  

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 22
                        color: searchButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2Disabled
                        text: "image_search"
                    }
                }  
            }  
              
            RowLayout {  
                id: statusRowLayout  
                anchors.left: parent.left  
                anchors.right: parent.right  
                anchors.bottom: parent.bottom  
                anchors.bottomMargin: 5  
                anchors.leftMargin: 10  
                anchors.rightMargin: 5  
                spacing: 8  
                  
                ApiInputBoxIndicator {  
                    icon: "wallpaper"  
                    text: currentService === "wallhaven" ? "Wallhaven" : "Unsplash"  
                    tooltipText: Translation.tr("Current service: %1\nSet it with %2service SERVICE").arg(currentService === "wallhaven" ? "Wallhaven" : "Unsplash").arg(root.commandPrefix)  
                } 

                ApiInputBoxIndicator {  
                    icon: "filter_alt"  
                    text: WallpaperBrowser.currentSortType  
                    tooltipText: Translation.tr("Current sort type: %1\nSet it with %2sort SORT_TYPE").arg(WallpaperBrowser.currentSortType).arg(root.commandPrefix)  
                }  
                  
                ApiInputBoxIndicator {  
                    icon: "key"  
                    text: ""  
                    tooltipText: Translation.tr("API key is set\nChange with %1api YOUR_API_KEY").arg(root.commandPrefix) 
                }  
                  
                Item { Layout.fillWidth: true }  
                  
                ButtonGroup {  
                    padding: 0  
                    Repeater {  
                        model: [  
                            { name: "service" },  
                            { name: "clear" }  
                        ]  
                        delegate: ApiCommandButton {  
                            property string commandRepresentation: `${root.commandPrefix}${modelData.name}`  
                            buttonText: commandRepresentation  
                            downAction: () => {  
                                if (modelData.name == "clear") {
                                    root.handleInput(commandRepresentation);
                                    return;
                                }
                                
                                searchInputField.text = commandRepresentation + " ";  
                                searchInputField.cursorPosition = searchInputField.text.length;  
                                searchInputField.forceActiveFocus();  
                            }  
                        }  
                    }  
                }  
            }  
        }  
    }

    

    Connections {
        target: WallpaperBrowser
        function onApiKeyChecked(status) {
            const msgs = {
                "ok": Translation.tr("Wallhaven knows this key: NSFW results are available."),
                "rejected": Translation.tr("Wallhaven doesn't accept this key. It is saved, but NSFW stays off until it is valid."),
                "unreachable": Translation.tr("Key saved, but Wallhaven couldn't be reached to check it."),
                "cleared": Translation.tr("Wallhaven API key removed.")
            };
            WallpaperBrowser.addSystemMessage(msgs[status] ?? status);
        }
    }

    property var allCommands: [  
        { name: "api", description: Translation.tr("Set API key for current service. Usage: %1api YOUR_API_KEY").arg(root.commandPrefix), execute: args => {
            const currentService = root.currentService;
            if (currentService === "wallhaven") {
                if (args.length === 0) {
                    WallpaperBrowser.addSystemMessage(WallpaperBrowser.wallhavenApiToken !== ""
                        ? Translation.tr("Wallhaven API key is set. Use %1api clear to remove it.").arg(root.commandPrefix)
                        : Translation.tr("No Wallhaven API key. It is optional: it unlocks NSFW results. Get one at https://wallhaven.cc/settings/account and set it with %1api YOUR_API_KEY").arg(root.commandPrefix));
                    return;
                }
                WallpaperBrowser.setWallhavenApiKey(args[0] === "clear" ? "" : args[0]);
                return;
            }
            if (args.length === 0) {
                if (WallpaperBrowser.unsplashApiToken != "") {
                    WallpaperBrowser.addSystemMessage(Translation.tr("Unsplash API key is already set"));
                } else {
                    WallpaperBrowser.addSystemMessage(Translation.tr("Unsplash API key not set. To get an API key: \n- Go to https://unsplash.com/developers and sign up/in \n- Create a new app in your apps page \n- Get the API key from Access Key and set it with %1api YOUR_API_KEY").arg(root.commandPrefix));
                }
                return;
            }
            if (args[0].length < 20) { // not a valid api key
                WallpaperBrowser.addSystemMessage(Translation.tr("Please provide a valid API key"));
                KeyringStorage.setNestedField(["apiKeys", `wallpapers_${currentService}`], "");
                return;
            }
            KeyringStorage.setNestedField(["apiKeys", `wallpapers_${currentService}`], args[0].trim());
            WallpaperBrowser.addSystemMessage(Translation.tr(`API key set for %1`).arg(currentService));
        } },
        { name: "service", description: Translation.tr("Change wallpaper service. Usage: %1service SERVICE").arg(root.commandPrefix), execute: args => {  
            if (args.length === 0) {  
                WallpaperBrowser.addSystemMessage(Translation.tr("Usage: %1service SERVICE, available services: \n\n Unsplash: \n- Requires API key, type %1api to get started. \n\nWallhaven: \n- API key optional (needed for NSFW) \n- You can search similar images").arg(root.commandPrefix));  
                return;  
            }  
            const service = args[0].toLowerCase();  
            if (service === "unsplash" || service === "wallhaven") {  
                WallpaperBrowser.setProvider(service);  
            } else {  
                WallpaperBrowser.addSystemMessage(Translation.tr("Invalid service. Use: unsplash or wallhaven"));  
            }  
        } }, 
        { name: "similar", description: Translation.tr("Find similar images (only for Wallhaven). Usage: %1similar WALLHAVEN_IMAGE_ID").arg(root.commandPrefix), execute: args => {
            const currentProvider = root.currentService;
            if (currentProvider !== "wallhaven") {
                WallpaperBrowser.addSystemMessage(Translation.tr("Similar images only works with wallhaven service"))
                return;
            }
            if (args.length === 0) {  
                WallpaperBrowser.addSystemMessage(Translation.tr("Usage: %1similar WALLHAVEN_IMAGE_ID").arg(root.commandPrefix));  
                return;  
            }  
            WallpaperBrowser.moreLikeThisPicture(args[0], 1);
            return; 
        } },
        { name: "anime", description: Translation.tr("Toggle anime results. Usage: %1anime SHOW/HIDE").arg(root.commandPrefix), execute: args => {  
            const currentProvider = root.currentService;
            if (currentProvider !== "wallhaven") {
                WallpaperBrowser.addSystemMessage(Translation.tr("Anime toggle only works with wallhaven service"))
                return;
            }
            if (args.length === 0) {  
                WallpaperBrowser.addSystemMessage(Translation.tr(`Anime results: %1. Available options: show, hide`).arg(WallpaperBrowser.showAnimeResults ? "visible" : "hidden"));  
                return;  
            }  
            if (args[0] !== "show" && args[0] !== "hide") {
                WallpaperBrowser.addSystemMessage(Translation.tr(`Available options: show, hide`));  
                return;
            }
            const showAnime = args[0] === "show" ? true : false; 
            WallpaperBrowser.addSystemMessage(Translation.tr(`Anime results: %1`).arg(showAnime ? "visible" : "hidden"));
            WallpaperBrowser.setAnimeResults(showAnime);  
        } },
        { name: "sort", description: Translation.tr("Sort results. Usage: %1sort SORT_OPTION").arg(root.commandPrefix), execute: args => {  
            const currentService = root.currentService;
            if (args.length === 0) {  
                if (currentService === "unsplash") {
                    WallpaperBrowser.addSystemMessage(Translation.tr("Please add a sort option\nAvailable sorts: relevant, latest"));
                    return;
                }

                if (currentService === "wallhaven") {
                    WallpaperBrowser.addSystemMessage(Translation.tr("Please add a sort option\nAvailable sorts: date_added, relevance, random, views, favorites, toplist, hot"));
                    return;
                }
            }  
            const sort = args[0].toLowerCase(); 
            if (currentService === "unsplash") {
                if (sort === "relevant" || sort === "latest") {
                    WallpaperBrowser.addSystemMessage(Translation.tr("Sort option is set to %1").arg(sort));
                    WallpaperBrowser.setSort(sort);
                } else {
                    WallpaperBrowser.addSystemMessage(Translation.tr("Invalid sort option. Use: relevant or latest"));
                }
            }
            if (currentService === "wallhaven") {
                if (sort === "date_added" || sort === "relevance" || sort === "random" || sort === "views" || sort === "favorites" || sort === "favourites" || sort === "toplist" || sort === "hot") {
                    WallpaperBrowser.addSystemMessage(Translation.tr("Sort option is set to %1").arg(sort));
                    WallpaperBrowser.setSort(sort);
                } else {
                    WallpaperBrowser.addSystemMessage(Translation.tr("Invalid sort option. Use: date_added, relevance, random, views, favorites, toplist, hot"));
                }
            }
        } }, 
        { name: "browse", description: Translation.tr("Show the sorted list without a search (Wallhaven)"), execute: () => {
            if (root.currentService !== "wallhaven") {
                WallpaperBrowser.addSystemMessage(Translation.tr("Browsing without a search only works with wallhaven service"));
                return;
            }
            WallpaperBrowser.makeRequest([], root.imageLimit, 1);
        } },
        { name: "purity", description: Translation.tr("Content filter: sfw, sketchy, nsfw (combine with commas). Usage: %1purity sfw,sketchy").arg(root.commandPrefix), execute: args => {
            const cfg = Config.options.wallhaven;
            if (args.length === 0) {
                WallpaperBrowser.addSystemMessage(Translation.tr("Purity: %1 (as sfw/sketchy/nsfw bits). Usage: %2purity sfw,sketchy,nsfw").arg(cfg.purity).arg(root.commandPrefix));
                return;
            }
            const want = args.join(",").toLowerCase().split(",").map(x => x.trim());
            const bad = want.filter(x => !["sfw", "sketchy", "nsfw"].includes(x));
            if (bad.length > 0 || want.length === 0) {
                WallpaperBrowser.addSystemMessage(Translation.tr("Use: sfw, sketchy, nsfw"));
                return;
            }
            cfg.purity = ["sfw", "sketchy", "nsfw"].map(x => want.includes(x) ? "1" : "0").join("");
            let note = Translation.tr("Purity set to %1").arg(want.join(", "));
            if (want.includes("nsfw") && WallpaperBrowser.wallhavenApiToken === "")
                note += "\n" + Translation.tr("NSFW is ignored until you set an API key with %1api YOUR_API_KEY").arg(root.commandPrefix);
            WallpaperBrowser.addSystemMessage(note);
        } },
        { name: "res", description: Translation.tr("Minimum resolution. Usage: %1res 1920x1080 (or off)").arg(root.commandPrefix), execute: args => {
            if (args.length === 0) {
                WallpaperBrowser.addSystemMessage(Translation.tr("Minimum resolution: %1").arg(Config.options.wallhaven.atleast || Translation.tr("any")));
                return;
            }
            const v = args[0].toLowerCase();
            if (v === "off" || v === "any") Config.options.wallhaven.atleast = "";
            else if (/^\d{3,5}x\d{3,5}$/.test(v)) Config.options.wallhaven.atleast = v;
            else { WallpaperBrowser.addSystemMessage(Translation.tr("Use a size like 1920x1080, or off")); return; }
            WallpaperBrowser.addSystemMessage(Translation.tr("Minimum resolution: %1").arg(Config.options.wallhaven.atleast || Translation.tr("any")));
        } },
        { name: "ratio", description: Translation.tr("Aspect ratios. Usage: %1ratio 16x9,16x10 (or off)").arg(root.commandPrefix), execute: args => {
            if (args.length === 0) {
                WallpaperBrowser.addSystemMessage(Translation.tr("Ratios: %1").arg(Config.options.wallhaven.ratios || Translation.tr("any")));
                return;
            }
            const v = args.join(",").toLowerCase();
            if (v === "off" || v === "any") Config.options.wallhaven.ratios = "";
            else if (/^\d+x\d+(,\d+x\d+)*$/.test(v)) Config.options.wallhaven.ratios = v;
            else { WallpaperBrowser.addSystemMessage(Translation.tr("Use ratios like 16x9 or 16x9,16x10, or off")); return; }
            WallpaperBrowser.addSystemMessage(Translation.tr("Ratios: %1").arg(Config.options.wallhaven.ratios || Translation.tr("any")));
        } },
        { name: "range", description: Translation.tr("Toplist time range: 1d, 3d, 1w, 1M, 3M, 6M, 1y. Usage: %1range 1w").arg(root.commandPrefix), execute: args => {
            const ranges = ["1d", "3d", "1w", "1M", "3M", "6M", "1y"];
            if (args.length === 0 || !ranges.includes(args[0])) {
                WallpaperBrowser.addSystemMessage(Translation.tr("Toplist range: %1. Options: %2").arg(Config.options.wallhaven.topRange).arg(ranges.join(", ")));
                return;
            }
            Config.options.wallhaven.topRange = args[0];
            WallpaperBrowser.addSystemMessage(Translation.tr("Toplist range: %1 (applies when sorting by toplist)").arg(args[0]));
        } },
        { name: "exclude", description: Translation.tr("Terms added to every search. Usage: %1exclude -people -portrait (or off)").arg(root.commandPrefix), execute: args => {
            if (args.length === 0) {
                WallpaperBrowser.addSystemMessage(Translation.tr("Excluded terms: %1").arg(Config.options.wallhaven.excludeTerms || Translation.tr("none")));
                return;
            }
            Config.options.wallhaven.excludeTerms = (args[0].toLowerCase() === "off") ? "" : args.join(" ");
            WallpaperBrowser.addSystemMessage(Translation.tr("Excluded terms: %1").arg(Config.options.wallhaven.excludeTerms || Translation.tr("none")));
        } },
        { name: "clear", description: Translation.tr("Clear the current list of images"), execute: () => {  
            WallpaperBrowser.clearResponses();  
        } },  
        { name: "help", description: Translation.tr("Shows a list of available commands"), execute: () => {  
            WallpaperBrowser.addSystemMessage(Translation.tr("Available commands are:\n- %1api API_KEY: Set API key for current service\n- %1service SERVICE: Change wallpaper service\n- %1similar IMAGE_ID: Find similar images, you must enter wallhaven image id thats located in the file name (e.g. wallhaven-lyz3d2.png's id is lyz3d2)\n- %1anime SHOW/HIDE: Toggle anime results (only for wallhaven service)\n- %1sort SORT_OPTION: Sort results\n- %1browse: Show the sorted list with no search (Wallhaven)\n- %1purity sfw,sketchy,nsfw: Content filter (Wallhaven)\n- %1res 1920x1080: Minimum resolution, or off\n- %1ratio 16x9: Aspect ratios, or off\n- %1range 1w: Toplist time range\n- %1exclude -people: Terms added to every search, or off\n- %1clear: Clear the current list of images\n- %1next: Load next page").arg(root.commandPrefix));
        } },
        { name: "next", description: Translation.tr("Load next page"), execute: () => {  
            console.log("[Wallpapers] Next page")
            if (root.responses.length > 0) {  
                const lastResponse = root.responses[root.responses.length - 1];  
                if (lastResponse.page > 0) {  
                    if (WallpaperBrowser.similarImageId != "") { // more like this feature
                        WallpaperBrowser.moreLikeThisPicture(WallpaperBrowser.similarImageId, lastResponse.page + 1)
                        return;
                    }
                    // normal search, next page
                    WallpaperBrowser.makeRequest(lastResponse.tags, root.imageLimit, lastResponse.page + 1);  
                }  
            }  
        } }
    ]  
      
    function handleInput(inputText) {
        responseListView.positionViewAtEnd()
        if (inputText.startsWith(root.commandPrefix)) {  
            const command = inputText.split(" ")[0].substring(1);  
            const args = inputText.split(" ").slice(1);  
            const commandObj = root.allCommands.find(cmd => cmd.name === `${command}`);  
            if (commandObj) {  
                commandObj.execute(args);  
            } else {  
                WallpaperBrowser.addSystemMessage(Translation.tr(`Unknown command: %1`).arg(command));  
            }  
        } else {  
            // Parse page number if present  
            const parts = inputText.split(" ");  
            let tags = [];  
            let page = 1;  
              
            parts.forEach(part => {  
                const pageNum = parseInt(part);  
                if (!isNaN(pageNum) && pageNum > 0) {  
                    page = pageNum;  
                } else if (part.trim().length > 0) {  
                    tags.push(part);  
                }  
            });  
              
            if (tags.length > 0) {  
                WallpaperBrowser.makeRequest(tags, root.imageLimit, page);  
            }  
        }  
    }  
}