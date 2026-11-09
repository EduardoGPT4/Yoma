package app.yomatv.mobile

data class DownloadPresentation(val label:String,val summary:String,val action:String,val actionable:Boolean,val progress:Int?,val error:String) {
    companion object {
        fun of(ep:Episode,paused:Boolean,running:Boolean):DownloadPresentation {
            val label=when{
                ep.state=="done"->"Completada"
                ep.state=="failed"->"Error"
                ep.state=="verifying"->"Verificando archivo"
                ep.state=="paused"||paused->"Pausada"
                ep.state=="downloading"&&running->"Descargando"
                else->"En cola"
            }
            val progress=if(ep.total>0)(ep.bytes.toDouble()/ep.total*1000).toInt().coerceIn(0,1000)else null
            val size=if(ep.total>0)"${progress!!/10} % · ${formatBytes(ep.bytes)} de ${formatBytes(ep.total)}" else if(ep.bytes>0)formatBytes(ep.bytes) else ""
            val explanation=when{
                ep.state=="retry"->"Reintento automático programado"
                ep.state=="queued"&&label!="Pausada"->"Espera su turno o la conexión permitida"
                else->""
            }
            val summary=listOf(label,size,explanation).filter{it.isNotBlank()}.joinToString(" · ")
            val action=when{
                ep.state=="done"->"Reproducir"
                ep.state=="failed"->"Reintentar"
                ep.state=="verifying"->"Verificando…"
                ep.state=="paused"||paused->"Continuar"
                else->"Pausar"
            }
            return DownloadPresentation(label,summary,action,ep.state!="verifying",progress,if(ep.state=="failed")shortError(ep.error)else "")
        }
        private fun shortError(value:String):String=when{
            value.contains("resolve",true)||value.contains("UnknownHost",true)||value.contains("DNS",true)->"No se pudo conectar con el servidor."
            value.contains("space",true)||value.contains("espacio",true)->"No hay espacio suficiente para guardar el capítulo."
            value.contains("404")||value.contains("403")->"El servidor no ofrece el video en este momento."
            value.contains("http",true)||value.contains("exception",true)||value.isBlank()->"No se pudo completar la descarga. Puedes reintentar."
            else->value.lineSequence().first().take(160)
        }
    }
}

fun episodeCaption(ep:Episode):String {
    val season=ep.payload.optString("season").replace(Regex("(invierno|primavera|verano|otoño)(\\d{4})"),"$1 $2").replaceFirstChar{it.uppercase()}
    return listOf(season,"Capítulo ${ep.number}",ep.language).filter{it.isNotBlank()}.joinToString(" · ")
}
