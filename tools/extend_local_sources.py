from pathlib import Path
p=Path('android/app/src/main/kotlin/app/yomashi/reader/LocalAnimePlatform.kt');s=p.read_text(encoding='utf-8-sig').replace('if(call.method=="resolve")network else commands','if(call.method in setOf("resolve","sources"))network else commands')
s=s.replace('''                        "resolve" -> {''','''                        "sources" -> {
                            val data=payload(call.arguments)
                            val page="https://animeav1.com/media/${data.getString("slug")}/${data.getString("number")}"
                            val html=Network.html(page,"page","https://animeav1.com/")
                            val embeds=JsData.property(html,"embeds") as? Map<*,*> ?: error("La fuente no devolvió servidores reconocibles.")
                            val items=org.json.JSONArray()
                            for((language,rows) in embeds) for(row in rows as? List<*> ?: emptyList<Any>()) {
                                val record=row as? Map<*,*> ?: continue
                                val url=record["url"] as? String ?: continue
                                val server=record["server"] as? String ?: continue
                                if(!url.startsWith("https://") || url.length>4096)continue
                                items.put(JSONObject().put("language",language.toString().uppercase()).put("server",server).put("embed",url).put("supported",server=="MP4Upload"&&Provider.allowed(url,"embed")))
                            }
                            items.toString()
                        }
                        "resolve" -> {''')
s=s.replace('val embed=Provider.embed(Network.html(page,"page","https://animeav1.com/"),data.optString("language","SUB"))','val embed=data.optString("embed").ifEmpty { Provider.embed(Network.html(page,"page","https://animeav1.com/"),data.optString("language","SUB")) }\n                            require(Provider.allowed(embed,"embed")){"Este servidor necesita el reproductor web."}')
p.write_text(s,encoding='utf-8')
p=Path('lib/features/anime/data/local_anime_downloads.dart');s=p.read_text(encoding='utf-8-sig').replace('Future<AnimePlaybackSource> resolve(AnimeTitle anime,AnimeEpisode episode,String language) async {','''Future<List<AnimeServer>> sources(AnimeTitle anime,AnimeEpisode episode) async {
    if(!Platform.isAndroid)throw const AnimeSourceFailureCompat('La reproducción de esta fuente está disponible en Android.');
    final data=jsonDecode((await channel.invokeMethod<String>('sources',jsonEncode(payload(anime,episode,'SUB'))))!) as List;
    return data.map((e)=>AnimeServer.fromJson(animeMap(e))).toList();
  }
  Future<AnimePlaybackSource> resolve(AnimeTitle anime,AnimeEpisode episode,String language,{String? embed}) async {''').replace("jsonEncode(payload(anime,episode,language))))!", "jsonEncode({...payload(anime,episode,language),'embed':?embed})))!")
p.write_text(s,encoding='utf-8')
p=Path('lib/features/anime/data/anime_controller.dart');s=p.read_text(encoding='utf-8-sig').replace('bool _disposed=false;','bool _disposed=false;\n  final activity=ValueNotifier<bool>(true);\n  String? _lastSnapshot;').replace('void setActive(bool active){','void setActive(bool active){activity.value=active;').replace("final data=await transfers.snapshot();if(_disposed)return;downloads=", "final data=await transfers.snapshot();if(_disposed)return;final fingerprint=data.toString();if(fingerprint==_lastSnapshot)return;_lastSnapshot=fingerprint;downloads=").replace('source.close();super.dispose();','source.close();activity.dispose();super.dispose();');p.write_text(s,encoding='utf-8')
