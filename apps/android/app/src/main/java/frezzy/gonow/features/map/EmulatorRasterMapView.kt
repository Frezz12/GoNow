package frezzy.gonow.features.map

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import frezzy.gonow.models.MapActivityResponse
import frezzy.gonow.models.MapBounds
import frezzy.gonow.models.MapCoordinate
import frezzy.gonow.models.MapViewport
import frezzy.gonow.models.PersistedMapCamera
import org.json.JSONArray
import org.json.JSONObject

/** Safe OSM fallback for x86 emulators; physical devices keep MapLibre. */
@Composable
fun EmulatorRasterMapView(
    modifier: Modifier,
    activities: List<MapActivityResponse>,
    userCoordinate: MapCoordinate?,
    selectedActivityId: String?,
    initialCamera: PersistedMapCamera?,
    onViewportIdle: (MapViewport) -> Unit,
    onCameraMove: (MapCoordinate) -> Unit,
    onActivityTap: (String) -> Unit,
    onMapTap: (MapCoordinate) -> Unit,
    pickerMode: Boolean
) {
    val bridge = remember { EmulatorMapBridge(onViewportIdle, onCameraMove, onActivityTap, onMapTap) }
    DisposableEffect(Unit) { onDispose { bridge.clear() } }

    AndroidView(
        modifier = modifier,
        factory = { context -> createEmulatorMap(context, bridge, initialCamera, pickerMode) },
        update = { webView ->
            val data = JSONObject().apply {
                put("activities", JSONArray().apply {
                    activities.forEach { activity ->
                        put(JSONObject().apply {
                            put("id", activity.id)
                            put("title", activity.title)
                            put("category", activity.category)
                            put("lat", activity.coordinate.latitude)
                            put("lon", activity.coordinate.longitude)
                            put("selected", activity.id == selectedActivityId)
                        })
                    }
                })
                put("user", userCoordinate?.let {
                    JSONObject().put("lat", it.latitude).put("lon", it.longitude)
                } ?: JSONObject.NULL)
            }
            // Compose can recompose for weather/location changes while the user is dragging.
            // Repainting every OSM tile here makes the emulator fallback feel like a bounded map.
            val payload = data.toString()
            if (webView.tag != payload) {
                webView.tag = payload
                webView.evaluateJavascript("if (window.updateMap) window.updateMap($payload);", null)
            }
        },
        onRelease = { webView ->
            webView.removeJavascriptInterface("GoNowMap")
            webView.stopLoading()
            webView.destroy()
        }
    )
}

private class EmulatorMapBridge(
    private var onViewportIdle: (MapViewport) -> Unit,
    private var onCameraMove: (MapCoordinate) -> Unit,
    private var onActivityTap: (String) -> Unit,
    private var onMapTap: (MapCoordinate) -> Unit
) {
    private val main = Handler(Looper.getMainLooper())

    @JavascriptInterface
    fun viewport(south: Double, west: Double, north: Double, east: Double, lat: Double, lon: Double, zoom: Double) {
        main.post { onViewportIdle(MapViewport(MapBounds(south, west, north, east), MapCoordinate(lat, lon), zoom)) }
    }

    @JavascriptInterface
    fun activity(id: String) = main.post { onActivityTap(id) }

    @JavascriptInterface
    fun camera(lat: Double, lon: Double) = main.post { onCameraMove(MapCoordinate(lat, lon)) }

    @JavascriptInterface
    fun mapTap(lat: Double, lon: Double) = main.post { onMapTap(MapCoordinate(lat, lon)) }

    fun clear() {
        onViewportIdle = {}
        onCameraMove = {}
        onActivityTap = {}
        onMapTap = {}
    }
}

@SuppressLint("SetJavaScriptEnabled")
private fun createEmulatorMap(
    context: android.content.Context,
    bridge: EmulatorMapBridge,
    camera: PersistedMapCamera?,
    pickerMode: Boolean
): WebView = WebView(context).apply {
    layoutParams = ViewGroup.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.MATCH_PARENT
    )
    settings.javaScriptEnabled = true
    settings.domStorageEnabled = false
    settings.allowFileAccess = false
    settings.allowContentAccess = false
    overScrollMode = WebView.OVER_SCROLL_NEVER
    webViewClient = object : WebViewClient() {
        override fun onPageFinished(view: WebView, url: String) {
            super.onPageFinished(view, url)
            (view.tag as? String)?.let { payload ->
                view.evaluateJavascript("if (window.updateMap) window.updateMap($payload);", null)
            }
        }
    }
    addJavascriptInterface(bridge, "GoNowMap")
    loadDataWithBaseURL(
        "https://gonow.local/",
        emulatorMapHtml(camera?.center?.latitude ?: 55.751244, camera?.center?.longitude ?: 37.618423, camera?.zoom ?: 10.0, pickerMode),
        "text/html",
        "UTF-8",
        null
    )
}

private fun emulatorMapHtml(initialLat: Double, initialLon: Double, initialZoom: Double, pickerMode: Boolean) = """
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
html,body,#map{margin:0;width:100%;height:100%;overflow:hidden;background:#f6f2f5;font-family:Arial,sans-serif}#map{touch-action:none}#layer{position:absolute;inset:0;will-change:transform}#tiles,#markers{position:absolute;inset:0}.tile{position:absolute;width:256px;height:256px;pointer-events:none}.marker{position:absolute;transform:translate(-50%,-82%) rotate(-45deg);width:34px;height:34px;border-radius:12px 12px 12px 4px;background:var(--pin,#7547e8);border:2px solid #fff;box-shadow:0 5px 12px #25124d55;z-index:2}.marker:after{content:'';position:absolute;width:11px;height:11px;border-radius:50%;background:#fff;left:10px;top:10px}.marker.selected{width:40px;height:40px;background:#7547e8;box-shadow:0 0 0 6px #7547e855,0 7px 16px #25124d66}.user{position:absolute;transform:translate(-50%,-50%);width:14px;height:14px;border-radius:50%;background:#e85ca8;border:3px solid white;box-shadow:0 0 0 7px #e85ca844;z-index:3}
</style></head><body><div id="map"><div id="layer"><div id="tiles"></div><div id="markers"></div></div></div><script>
const map=document.getElementById('map'),layer=document.getElementById('layer'),tilesLayer=document.getElementById('tiles'),markersLayer=document.getElementById('markers'),pickerMode=$pickerMode;let lat=$initialLat,lon=$initialLon,zoom=$initialZoom,data={activities:[],user:null},drag=null,pinch=null,notifyTimer;const pointers=new Map(),tiles=new Map();const pinColors={walking:'#2e9d62',sport:'#ef5350',travel:'#3f8cff',music:'#a855f7',games:'#5b5ce2',food:'#f59e0b',help:'#14a38b',education:'#8b5a3c',animals:'#16a36a',event:'#ec5a9a',other:'#7a7785'};
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));const world=()=>256*Math.pow(2,zoom);const rad=x=>x*Math.PI/180;
function project(a,b){const s=world(),q=clamp(a,-85.0511,85.0511),sn=Math.sin(rad(q));return{x:(b+180)/360*s,y:(0.5-Math.log((1+sn)/(1-sn))/(4*Math.PI))*s}}
function unproject(x,y){const s=world(),n=Math.PI-2*Math.PI*y/s;return{lat:180/Math.PI*Math.atan(0.5*(Math.exp(n)-Math.exp(-n))),lon:x/s*360-180}}
function center(){return project(lat,lon)}function screen(a,b){const c=center(),w=map.clientWidth,h=map.clientHeight,p=project(a,b),s=world();let dx=p.x-c.x;if(dx>s/2)dx-=s;else if(dx<-s/2)dx+=s;return{x:w/2+dx,y:h/2+p.y-c.y}}
function renderTiles(){const w=map.clientWidth,h=map.clientHeight,c=center(),left=c.x-w/2,top=c.y-h/2,z=Math.round(zoom),n=Math.pow(2,z),margin=256,needed=new Set();for(let x=Math.floor((left-margin)/256);x<=Math.floor((left+w+margin)/256);x++)for(let y=Math.floor((top-margin)/256);y<=Math.floor((top+h+margin)/256);y++)if(y>=0&&y<n){const wrapped=(x%n+n)%n,key=z+'/'+wrapped+'/'+y;needed.add(key);let img=tiles.get(key);if(!img){img=document.createElement('img');img.className='tile';img.draggable=false;img.decoding='async';img.src='https://tile.openstreetmap.org/'+key+'.png';tiles.set(key,img);tilesLayer.appendChild(img)}img.style.left=(x*256-left)+'px';img.style.top=(y*256-top)+'px'}tiles.forEach((img,key)=>{if(!needed.has(key)){img.remove();tiles.delete(key)}})}
function renderMarkers(){while(markersLayer.firstChild)markersLayer.removeChild(markersLayer.firstChild);data.activities.forEach(a=>{const p=screen(a.lat,a.lon),e=document.createElement('div');e.className='marker'+(a.selected?' selected':'');e.style.setProperty('--pin',pinColors[a.category]||pinColors.other);e.title=a.title;e.style.left=p.x+'px';e.style.top=p.y+'px';e.onclick=t=>{t.stopPropagation();GoNowMap.activity(a.id)};markersLayer.appendChild(e)});if(data.user){const p=screen(data.user.lat,data.user.lon),e=document.createElement('div');e.className='user';e.style.left=p.x+'px';e.style.top=p.y+'px';markersLayer.appendChild(e)}}
function render(){renderTiles();renderMarkers()}let renderFrame=0;function renderSoon(){if(renderFrame)return;renderFrame=requestAnimationFrame(()=>{renderFrame=0;render()})}
const normalizeLon=value=>((value+540)%360)-180;function scheduleNotify(){clearTimeout(notifyTimer);notifyTimer=setTimeout(()=>{const c=center(),nw=unproject(c.x-map.clientWidth/2,c.y-map.clientHeight/2),se=unproject(c.x+map.clientWidth/2,c.y+map.clientHeight/2);GoNowMap.viewport(clamp(se.lat,-85.0511,85.0511),normalizeLon(nw.lon),clamp(nw.lat,-85.0511,85.0511),normalizeLon(se.lon),lat,lon,zoom)},250)}
function setCenterWorld(x,y){const p=unproject(x,y);lat=clamp(p.lat,-85.0511,85.0511);lon=((p.lon+540)%360)-180}function move(dx,dy){const c=center();setCenterWorld(c.x-dx,c.y-dy)}function zoomBy(delta,x=map.clientWidth/2,y=map.clientHeight/2){const c=center(),before=unproject(c.x+x-map.clientWidth/2,c.y+y-map.clientHeight/2);zoom=clamp(zoom+delta,2,18);const anchored=project(before.lat,before.lon);setCenterWorld(anchored.x-x+map.clientWidth/2,anchored.y-y+map.clientHeight/2);render();scheduleNotify()}function resetPreview(){layer.style.transform='';layer.style.transformOrigin='center center'}function pair(){return Array.from(pointers.values()).slice(0,2)}function distance(a,b){return Math.hypot(a.x-b.x,a.y-b.y)}function midpoint(a,b){return{x:(a.x+b.x)/2,y:(a.y+b.y)/2}}
map.addEventListener('pointerdown',e=>{map.setPointerCapture(e.pointerId);pointers.set(e.pointerId,{x:e.clientX,y:e.clientY});if(pointers.size===1){drag={id:e.pointerId,startX:e.clientX,startY:e.clientY,x:e.clientX,y:e.clientY,moved:false};pinch=null}else if(pointers.size===2){const[a,b]=pair(),mid=midpoint(a,b);drag=null;pinch={distance:distance(a,b),scale:1,x:mid.x,y:mid.y}}});map.addEventListener('pointermove',e=>{if(!pointers.has(e.pointerId))return;pointers.set(e.pointerId,{x:e.clientX,y:e.clientY});if(pinch&&pointers.size>=2){const[a,b]=pair(),mid=midpoint(a,b);pinch.scale=clamp(distance(a,b)/pinch.distance,.5,2.5);pinch.x=mid.x;pinch.y=mid.y;layer.style.transformOrigin=mid.x+'px '+mid.y+'px';layer.style.transform='scale('+pinch.scale+')';return}if(!drag||drag.id!==e.pointerId)return;const dx=e.clientX-drag.x,dy=e.clientY-drag.y;if(Math.abs(e.clientX-drag.startX)+Math.abs(e.clientY-drag.startY)>3)drag.moved=true;if(dx||dy){move(dx,dy);renderSoon()}drag.x=e.clientX;drag.y=e.clientY;if(pickerMode)GoNowMap.camera(lat,lon)});function finishPointer(e){const activePinch=pinch;pointers.delete(e.pointerId);if(activePinch){if(pointers.size<2){resetPreview();pinch=null;zoomBy(Math.log2(activePinch.scale),activePinch.x,activePinch.y)}return}if(!drag||drag.id!==e.pointerId)return;if(drag.moved){resetPreview();render();scheduleNotify()}else{const c=center(),p=unproject(c.x+e.clientX-map.clientWidth/2,c.y+e.clientY-map.clientHeight/2);if(pickerMode){lat=p.lat;lon=p.lon;render();scheduleNotify()}GoNowMap.mapTap(p.lat,p.lon)}drag=null}map.addEventListener('pointerup',finishPointer);map.addEventListener('pointercancel',finishPointer);window.updateMap=d=>{data=d;renderMarkers()};window.addEventListener('resize',()=>{render();scheduleNotify()});render();scheduleNotify();
</script></body></html>
""".trimIndent()
