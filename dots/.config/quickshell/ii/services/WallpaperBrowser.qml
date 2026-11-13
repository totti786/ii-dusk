pragma Singleton  
pragma ComponentBehavior: Bound  
  
import qs.modules.common  
import qs.services  
import Quickshell;  
import QtQuick;  
  
/**  
 * A service for interacting with wallpaper APIs (Unsplash and Wallhaven).  
 */  
Singleton {  
    id: root  
    property Component unsplashResponseDataComponent: WallpaperResponseData {}  
  
    signal tagSuggestion(string query, var suggestions)  
    signal responseFinished()  
  
    property string unsplashApiToken: KeyringStorage.keyringData?.apiKeys?.wallpapers_unsplash ?? ""
    property string wallhavenApiToken: Config.options.wallhaven?.apiKey ?? ""  
    property string failMessage: Translation.tr("That didn't work. Tips:\n- Check your search query\n- Try different keywords\n- Check your API key under settings")  
    property var responses: []
    property int runningRequests: 0
    property string errorMessage: ""
    property var providerList: ["unsplash", "wallhaven"]  
    property var currentProvider: Config.options.wallpapers.service ?? "wallhaven" // defaulting to wallhaven bc it doesnt require api key

    // Wallhaven spells the sort "favorites"; its API ignores "favourites" without an error.
    function normalizeSort(sort) {
        const s = String(sort ?? "").toLowerCase()
        return s === "favourites" ? "favorites" : s
    }
    property string currentSortType: normalizeSort(Config.options.wallpapers.sort ?? "favorites") // Options for wallhaven: date_added, relevance, random, views, favourites, toplist // Options for unsplash: relevant, latest
    property bool showAnimeResults: Config.options.wallpapers.showAnimeResults ?? false

    property string similarImageId: ""
    property string randomSeed: ""
    // NSFW needs an API key; without one wallhaven would answer 401 for the whole search.
    readonly property string effectivePurity: {
        const p = String(Config.options.wallhaven?.purity ?? "100")
        return (p[2] === "1" && !root.wallhavenApiToken) ? p.substring(0, 2) + "0" : p
    }
    // general / anime / people; the older "show anime" switch still turns the middle one on.
    readonly property string effectiveCategories: {
        const c = String(Config.options.wallhaven?.categories ?? "100").padEnd(3, "0").substring(0, 3)
        const withAnime = root.showAnimeResults ? c[0] + "1" + c[2] : c
        return withAnime === "000" ? "100" : withAnime
    }
    property var currentSearchTags: []
    
    property var providers: {  
        "system": { "name": Translation.tr("System") },  
        "unsplash": {  
            "name": "Unsplash",  
            "url": "https://unsplash.com",  
            "api": "https://api.unsplash.com/search/photos",            
            "description": Translation.tr("High quality photos from Unsplash"),  
            "mapFunc": (response) => {  
                const items = Array.isArray(response.results) ? response.results : [];
                return items.map(item => {  
                    return {  
                        "id": item.id,  
                        "width": item.width,  
                        "height": item.height,  
                        "aspect_ratio": item.width / item.height,  
                        "tags": item.tags ? item.tags.map(tag => tag.title).join(" ") : (item.alt_description || item.description || "wallpaper"),  
                        "rating": "s",  
                        "is_nsfw": false,  
                        "md5": item.id,  
                        "preview_url": item.urls.small,  
                        "sample_url": item.urls.full,  
                        "file_url": item.urls.full,  
                        "file_ext": "jpg",  
                        "source": item.links.html,  
                        "author": item.user.name,  
                        "author_url": item.user.links.html,
                        "color": item.color || ""
                    }  
                })  
            },  
            "tagSearchTemplate": "https://api.unsplash.com/search/collections",  
            "tagMapFunc": (response) => {  
                return response.results.slice(0, 10).map(item => {  
                    return {  
                        "name": item.title.toLowerCase().replace(/\s+/g, '-'),  
                        "displayName": item.title,  
                        "count": item.total_photos,  
                        "description": item.description || ""  
                    }  
                })  
            }  
        },  
        "wallhaven": {  
            "name": "Wallhaven",  
            "url": "https://wallhaven.cc",  
            "api": "https://wallhaven.cc/api/v1/search",  
            "description": Translation.tr("Wallpapers | Advanced search with ratios, resolutions, categories, sorting"),  
            "mapFunc": (response) => {  
                console.log("[Wallpapers] Wallhaven response structure: " + JSON.stringify(Object.keys(response)))  
                if (!response.data) {  
                    console.log("[Wallpapers] Wallhaven response has no data field")  
                    return [];  
                }  
                if (!Array.isArray(response.data)) {  
                    console.log("[Wallpapers] Wallhaven response.data is not an array: " + typeof response.data)  
                    return [];  
                }  
                console.log("[Wallpapers] Wallhaven found " + response.data.length + " items")  
                response = response.data  
                return response.map(item => {  
                    return {  
                        "id": item.id,  
                        "width": item.dimension_x || 1920,  
                        "height": item.dimension_y || 1080,  
                        "aspect_ratio": (item.dimension_x || 1920) / (item.dimension_y || 1080),  
                        "tags": item.tags && Array.isArray(item.tags) ? item.tags.map(tag => tag.name).join(" ") : "",  
                        "rating": item.purity === 'sfw' ? 's' : item.purity === 'sketchy' ? 'q' : 'e',  
                        "is_nsfw": item.purity !== 'sfw',  
                        "md5": item.id,  
                        "preview_url": item.thumbs && item.thumbs.original ? item.thumbs.original : item.path,  
                        "sample_url": item.thumbs && item.thumbs.small ? item.thumbs.small : item.path,  
                        "file_url": item.path,  
                        "file_ext": item.file_type ? item.file_type.split('/')[1] : 'jpg',  
                        "source": item.source || "",
                        "color": item.colors[0] || ""  
                    }  
                })  
            },  
            "tagSearchTemplate": "https://wallhaven.cc/api/v1/search",  
            "tagMapFunc": (response) => {  
                if (!response.data) return [];  
                return response.data.slice(0, 10).map(item => {  
                    return {  
                        "name": item.tags && item.tags.length > 0 ? item.tags[0].name : "",  
                        "count": ""  
                    }  
                })  
            }  
        }  
    }  

    function setSort(sort) {
        sort = root.normalizeSort(sort)
        Config.options.wallpapers.sort = sort
    }

    function setAnimeResults(show) {
        Config.options.wallpapers.showAnimeResults = show
    }
  
    function setProvider(provider) {  
        provider = provider.toLowerCase()  
        if (providerList.indexOf(provider) !== -1) {  
            Config.options.wallpapers.service = provider
            root.addSystemMessage(Translation.tr("Provider set to ") + providers[provider].name) 
            if (provider === "unsplash") {
                root.currentSortType = "relevance" // default value
            } 
            if (provider === "wallhaven") {
                root.currentSortType = "favorites" // default value
            }
        } else {  
            root.addSystemMessage(Translation.tr("Invalid API provider. Supported: \n- ") + providerList.join("\n- "))  
        }  
    }  
  
    function clearResponses() {  
        responses = []
        root.currentSearchTags = []
        root.errorMessage = ""
    }  
  
    function addSystemMessage(message) {  
        responses = [...responses, root.unsplashResponseDataComponent.createObject(null, {  
            "provider": "system",  
            "tags": [],  
            "page": -1,  
            "images": [],  
            "message": message  
        })]  
    }  

    function addSimilarImageMessage(message, fileUrl) {  
        responses = [...responses, root.unsplashResponseDataComponent.createObject(null, {  
            "provider": "system",  
            "tags": [],  
            "page": -1,  
            "images": [],  
            "message": message,
            "filePath": fileUrl
        })]  
    }  
  
    // The query for one page of Wallhaven results, whichever service the sidebar is on: the deck
    // picker asks for it too. `tags` is a list of search words (empty for the plain sorted list).
    function wallhavenParams(tags, page, imageId = "") {
        const params = []
        const tagString = tags.join(" ")
        const wh = Config.options.wallhaven
        if (imageId !== "") { // 'More like this picture' feature
            params.push(`q=like%3A${imageId}`) // idk why but api has to be configured like this, learned it in the hard way
            params.push(`sorting=relevance`)
            params.push(`order=desc`)
            root.similarImageId = imageId
        } else { // a search, or with no tags the plain sorted list
            const query = tagString.trim().length > 0 ? `${tagString} ${wh.excludeTerms ?? ""}`.trim() : ""
            if (query.length > 0)
                params.push("q=" + encodeURIComponent(query))
            params.push(`sorting=${root.currentSortType}`)
            params.push(`order=${wh.order || "desc"}`)
            if (root.currentSortType === "toplist")
                params.push(`topRange=${wh.topRange || "1M"}`)
            if (root.currentSortType === "random" && page > 1 && root.randomSeed.length > 0)
                params.push(`seed=${root.randomSeed}`) // pages through the shuffle page 1 gave
            if (wh.atleast) params.push(`atleast=${encodeURIComponent(wh.atleast)}`)
            if (wh.ratios) params.push(`ratios=${encodeURIComponent(wh.ratios)}`)
            root.similarImageId = ""
        }
        if (imageId === "" && wh.colors) params.push(`colors=${encodeURIComponent(wh.colors)}`)
        params.push(`categories=${root.effectiveCategories}`)
        params.push(`purity=${root.effectivePurity}`)
        params.push(`page=${page}`)
        return params
    }

    function constructRequestUrl(tags, limit=20, page=1, imageId="") {
        var provider = providers[currentProvider]  
        var baseUrl = provider.api  
        var url = baseUrl  
        var tagString = tags.join(" ")  
        var params = []  
          
         if (currentProvider === "unsplash") {
             if (tagString.trim().length > 0) {
                 params.push("query=" + encodeURIComponent(tagString))
             }
             params.push("per_page=" + Math.min(limit, 30))
             params.push("page=" + page)
             params.push(`order_by=${root.currentSortType}`)
             params.push("orientation=landscape")
         
             params.push("client_id=" + encodeURIComponent(root.unsplashApiToken))
         }

        else if (currentProvider === "wallhaven") {
            params = root.wallhavenParams(tags, page, imageId)
        }

        if (baseUrl.indexOf("?") === -1) {  
            url += "?" + params.join("&")  
        } else {  
            url += "&" + params.join("&")  
        }  
        return url  
    }  

    function moreLikeThisPicture(imageId, page=1) { // Uses built-in wallhaven's 'More like this picture' feature
        if (root.currentProvider !== "wallhaven") {
            root.addSystemMessage(Translation.tr("'More like this picture' feature only works with wallhaven service"))
            return;
        }
        root.currentSearchTags = [Translation.tr("Similar to ") + imageId]
        makeRequest([], 20, page, imageId)       
    }

    // Not used for now, but could be usefull in the future
    function getTags(imageId, callback) {
        if (currentProvider !== "wallhaven") {
            // console.log("[Wallpapers] getTags only works with wallhaven (for now, unsplash support will be added)")
            // root.addSystemMessage(Translation.tr("getTags only works with wallhaven (for now, unsplash support will be added)"))
            return;
        }
        
        var url = `https://wallhaven.cc/api/v1/w/${imageId}`
        // console.log("[Wallpapers] Fetching tags from " + url)
        
        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText)
                    if (response.data && response.data.tags) {
                        var tags = response.data.tags.map(tag => tag.name).join(" ")
                        // console.log("[Wallpapers] Tags for " + imageId + ": " + tags)
                        
                        if (callback && typeof callback === "function") {
                            callback(tags, response.data.tags)
                        }
                    }
                } catch (e) {
                    // console.log("[Wallpapers] Failed to parse tags response: " + e)
                    if (callback && typeof callback === "function") {
                        callback("", [])
                    }
                }
            }
            else if (xhr.readyState === XMLHttpRequest.DONE) {
                // console.log("[Wallpapers] getTags failed with status: " + xhr.status)
                if (callback && typeof callback === "function") {
                    callback("", [])
                }
            }
        }
        
        try {
            if (root.wallhavenApiToken) {
                xhr.setRequestHeader("X-API-Key", root.wallhavenApiToken)
            }
            xhr.send()
        } catch (error) {
            // console.log("[Wallpapers] Could not fetch tags:", error)
            if (callback && typeof callback === "function") {
                callback("", [])
            }
        }
    }
  
    function httpFailMessage(status) {
        if (status === 401) return Translation.tr("Wallhaven rejected the API key (HTTP 401). Check it with the api command.")
        if (status === 429) return Translation.tr("Wallhaven is rate limiting you (HTTP 429). Wait a minute and try again.")
        if (status >= 500) return Translation.tr("Wallhaven had a server error (HTTP %1). Try again later.").arg(status)
        if (status === 0) return Translation.tr("Couldn't reach the wallpaper service. Check your connection.")
        return root.failMessage
    }

    function makeRequest(tags, limit=20, page=1, imageId="") { // image id is used for "more like this" feature
        if (imageId === "") {
            root.currentSearchTags = tags;
        }
        root.errorMessage = "";
        var url = constructRequestUrl(tags, limit, page, imageId)  
        console.log("[Wallpapers] Making request to " + url)  
  
        const newResponse = root.unsplashResponseDataComponent.createObject(null, {  
            "provider": currentProvider,  
            "tags": tags,  
            "page": page,  
            "images": [],  
            "message": ""
        })  
  
        var xhr = new XMLHttpRequest()  
        xhr.open("GET", url)  
        xhr.onreadystatechange = function() {  
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {  
                try {  
                    const provider = providers[currentProvider]  
                    let response = JSON.parse(xhr.responseText)  
                    if (currentProvider === "wallhaven" && page === 1)
                        root.randomSeed = response.meta?.seed ?? ""
                    response = provider.mapFunc(response)  

                    /* if (currentProvider === "wallhaven") { // can be used to set a limit to wallhaven (currently there is not), but not using it as it breaks the page sync
                        response = response.slice(0, limit)
                    } */

                    newResponse.images = response  
                    newResponse.message = response.length > 0 ? "" : root.failMessage
                      
                } catch (e) {  
                    console.log("[Wallpapers] Failed to parse response: " + e)  
                    newResponse.message = root.failMessage  
                    root.errorMessage = root.failMessage;
                } finally {  
                    root.runningRequests--;  
                    root.responses = [...root.responses, newResponse]  
                }  
            }  
            else if (xhr.readyState === XMLHttpRequest.DONE) {  
                console.log("[Wallpapers] Request failed with status: " + xhr.status)  
                const reason = root.httpFailMessage(xhr.status)
                newResponse.message = reason
                root.errorMessage = reason;
                root.runningRequests--;  
                root.responses = [...root.responses, newResponse]  
            }  
            root.responseFinished()  
        }  
  
        try {  
            if (currentProvider === "unsplash") {  
                xhr.setRequestHeader("Authorization", "Client-ID " + root.unsplashApiToken)  
            } else if (currentProvider === "wallhaven" && root.wallhavenApiToken) {  
                xhr.setRequestHeader("X-API-Key", root.wallhavenApiToken)  
            }  
            root.runningRequests++;  
            xhr.send()  
        } catch (error) {  
            console.log("Could not set headers:", error)  
            root.errorMessage = root.failMessage;
            root.runningRequests = Math.max(0, root.runningRequests - 1);
        }     
    }  
  
    // Download one result. Skips what is already on disk, writes through a .part file so a
    // half-written or HTTP-error download never shows up as a wallpaper, and records the id in
    // the same history file the walldl script keeps, so neither downloads it again.
    // $1 dir, $2 url, $3 file name, $4 wallhaven id, $5 "print" to write the saved path to stdout
    // instead of notifying (the deck picker sets the wallpaper from it).
    readonly property string downloadScript: `
        dir="$1"; url="$2"; name="$3"; id="$4"; quiet="$5"; hist="$HOME/.local/share/walldl/history"
        mkdir -p "$dir" "$(dirname "$hist")"
        note() { [ -n "$id" ] && ! grep -qxF "$id" "$hist" 2>/dev/null && echo "$id" >> "$hist"; }
        done_msg() { if [ -n "$quiet" ]; then printf '%s' "$dir/$name"; else notify-send -a Shell -i "$dir/$name" "$1" "$dir/$name"; fi; }
        if [ -s "$dir/$name" ]; then note; done_msg "${Translation.tr("Already downloaded")}"; exit 0; fi
        if curl -fsSL "$url" -o "$dir/$name.part" && [ -s "$dir/$name.part" ]; then
            mv "$dir/$name.part" "$dir/$name" && note && done_msg "${Translation.tr("Download complete")}"
        else
            rm -f "$dir/$name.part"; notify-send -a Shell -u critical "${Translation.tr("Download failed")}" "$name"; exit 1
        fi`

    // Where a search's downloads go: the download folder, or a subfolder named after the search.
    function downloadDirFor(targetDir, tags) {
        const words = (tags ?? root.currentSearchTags).join(" ")
        if (Config.options.wallhaven?.tagSubfolders && words.trim().length > 0)
            return targetDir + "/" + words.replace(/\//g, "_").replace(/\.\./g, "").trim().substring(0, 100)
        return targetDir
    }

    function downloadImage(imageData, targetDir) {
        const fileName = decodeURIComponent(imageData.file_url.substring(imageData.file_url.lastIndexOf('/') + 1))
        const dir = currentProvider === "wallhaven" ? root.downloadDirFor(targetDir) : targetDir
        Quickshell.execDetached(["bash", "-c", root.downloadScript, "_", dir, imageData.file_url, fileName, imageData.id ?? "", ""])
    }

    // Saves the key and asks wallhaven whether it knows it.
    signal apiKeyChecked(string status) // "ok" | "rejected" | "unreachable" | "cleared"
    function setWallhavenApiKey(key) {
        key = String(key ?? "").trim()
        Config.options.wallhaven.apiKey = key
        if (key.length === 0) { root.apiKeyChecked("cleared"); return }
        const xhr = new XMLHttpRequest()
        xhr.open("GET", "https://wallhaven.cc/api/v1/settings")
        xhr.setRequestHeader("X-API-Key", key)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            root.apiKeyChecked(xhr.status === 200 ? "ok" : ([401, 403, 404].includes(xhr.status) ? "rejected" : "unreachable")) // an unknown key answers 404
        }
        xhr.send()
    }

    property var currentTagRequest: null  
    function triggerTagSearch(query) {  
        if (currentTagRequest) {  
            currentTagRequest.abort();  
        }  
  
        var provider = providers[currentProvider]  
        if (!provider.tagSearchTemplate) {  
            return  
        }  
          
        var url = provider.tagSearchTemplate  
        if (currentProvider === "unsplash") {  
            url += "?query=" + encodeURIComponent(query) + "&per_page=10"  
        } else if (currentProvider === "wallhaven") {  
            url += "?q=" + encodeURIComponent(query)  
        }  
  
        var xhr = new XMLHttpRequest()  
        currentTagRequest = xhr  
        xhr.open("GET", url)  
        xhr.onreadystatechange = function() {  
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {  
                currentTagRequest = null  
                try {  
                    var response = JSON.parse(xhr.responseText)  
                    response = provider.tagMapFunc(response)  
                    root.tagSuggestion(query, response)  
                } catch (e) {  
                    console.log("[Wallpapers] Failed to parse tag suggestions: " + e)  
                }  
            }  
            else if (xhr.readyState === XMLHttpRequest.DONE) {  
                console.log("[Wallpapers] Tag search failed with status: " + xhr.status)  
            }  
        }  
  
        try {  
            if (currentProvider === "unsplash") {  
                xhr.setRequestHeader("Authorization", "Client-ID " + root.unsplashApiToken)  
            } else if (currentProvider === "wallhaven" && root.wallhavenApiToken) {  
                xhr.setRequestHeader("X-API-Key", root.wallhavenApiToken)  
            }  
            xhr.send()  
        } catch (error) {  
            console.log("Could not set headers:", error)  
        }     
    }  
}
