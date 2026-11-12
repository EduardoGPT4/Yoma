package app.yomatv.mobile

import app.yomashi.reader.R
import app.yomashi.reader.BuildConfig

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.graphics.drawable.ClipDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.*

data class DownloadSnapshot(val owner:Long,val jobs:List<Episode>,val filter:String,val group:String?,val running:Boolean,val paused:Boolean,val wifi:Boolean,val free:Long)
data class DownloadActions(
    val filter:(String)->Unit,val group:(String?)->Unit,val toggle:(Episode)->Unit,
    val options:(Episode)->Unit,val cancel:(Episode)->Unit,val pauseAll:()->Unit,
    val storage:()->Unit,val wifi:(Boolean)->Unit,val status:(Episode)->String
)

/** One retained view tree. Transfer ticks bind values without replacing scroll content. */
class DownloadsPanel(context:Context,private val actions:DownloadActions):ScrollView(context) {
    private val body=LinearLayout(context).apply{orientation=LinearLayout.VERTICAL;setPadding(context.dp(18),context.dp(12),context.dp(18),context.dp(24))}
    private val main=column();private val detail=column()
    private val used=text("",18).apply{typeface=Typeface.create("sans-serif-medium",Typeface.NORMAL)};private val available=text("",14)
    private val storageBar=track(YomaColors.ACCENT)
    private val filterButtons=linkedMapOf<String,Button>()
    private val activeTitle=text("",23,true);private val activeRows=column()
    private val readyTitle=text("Listas para ver",23,true);private val readyRows=column()
    private val waitingTitle=text("Pendientes",23,true);private val waitingRows=column();private val waitingViews=linkedMapOf<String,ReadyRow>()
    private val edit=link("Editar"){editing=!editing;refresh()}
    private val pauseAll=icon("pause","Pausar todas las descargas"){actions.pauseAll()}
    private val empty=text("",16)
    private val activeViews=linkedMapOf<String,TransferRow>();private val readyViews=linkedMapOf<String,ReadyRow>()
    private val detailViews=linkedMapOf<String,EpisodeRow>()
    private val detailRows=column();private val detailTitle=text("",25,true);private val detailEmpty=text("No hay capítulos en este filtro.",16)
    private val wifi=Switch(context).apply{text="Descargar solo con Wi-Fi";textSize=14f;includeFontPadding=false;minHeight=context.dp(48);switchPadding=context.dp(12);setTextColor(PAPER)}
    private var snapshot:DownloadSnapshot?=null;private var editing=false;private var binding=false
    private var route="";private var routeChanged=false;private var lastShape="";private val positions=mutableMapOf<String,Int>()
    private var restoreScroll:Int?=null;private var restoreAnchor:Triple<View,Int,String>?=null

    init {
        tag="downloads-panel";isFillViewport=true;setBackgroundColor(INK);addView(body)
        body.addView(main);body.addView(detail)
        main.addView(text("Descargas",36,true));main.addView(text("Tus episodios, donde quieras",16).apply{setTextColor(MUTED)},lp(top=4,bottom=14))
        val storage=box();val storageRow=row()
        storageRow.addView(NavGlyph(context,"storage").apply{tint=YomaColors.TEXT_SECONDARY},LinearLayout.LayoutParams(context.dp(30),context.dp(32)).apply{rightMargin=context.dp(14)})
        val numbers=column();val caption=row()
        caption.addView(used,LinearLayout.LayoutParams(0,-2,1f));caption.addView(available.apply{setTextColor(MUTED)})
        numbers.addView(caption);val storageTools=row();storageTools.addView(storageBar,LinearLayout.LayoutParams(0,context.dp(6),1f));storageTools.addView(link("Administrar →"){actions.storage()},LinearLayout.LayoutParams(-2,-2).apply{leftMargin=context.dp(10)});numbers.addView(storageTools,lp(top=4))
        storageRow.addView(numbers,LinearLayout.LayoutParams(0,-2,1f));storage.addView(storageRow);main.addView(storage)
        val tabs=row().apply{isBaselineAligned=false}
        for((key,name)in listOf("all" to "Todas","active" to "En curso","done" to "Completadas")){
            val b=pill(name){actions.filter(key)}.apply{tag="download-filter-$key"}
            filterButtons[key]=b;tabs.addView(b,LinearLayout.LayoutParams(0,-1,1f).apply{if(key!="done")rightMargin=context.dp(8)})
        }
        main.addView(tabs,lp(top=14,bottom=14))
        val activeHeading=row();activeHeading.addView(activeTitle,LinearLayout.LayoutParams(0,-2,1f));activeHeading.addView(pauseAll)
        main.addView(activeHeading);main.addView(activeRows,lp(top=8,bottom=8))
        val readyHeading=row();readyHeading.addView(readyTitle,LinearLayout.LayoutParams(0,-2,1f));readyHeading.addView(edit)
        main.addView(readyHeading);main.addView(readyRows,lp(top=8,bottom=12))
        readyRows.background=outlined(SURFACE,context.dp(18).toFloat());readyRows.clipToOutline=true
        main.addView(waitingTitle,lp(top=8,bottom=8));main.addView(waitingRows,lp(bottom=12));waitingRows.background=outlined(SURFACE,context.dp(18).toFloat());waitingRows.clipToOutline=true
        main.addView(empty,lp(top=12,bottom=16))
        val wifiBox=box().apply{setPadding(context.dp(14),0,context.dp(14),0)};val wifiRow=row()
        wifiRow.addView(NavGlyph(context,"wifi").apply{tint=YomaColors.TEXT_SECONDARY},LinearLayout.LayoutParams(context.dp(24),context.dp(24)).apply{rightMargin=context.dp(12)})
        wifiRow.addView(wifi,LinearLayout.LayoutParams(0,-2,1f));wifiBox.addView(wifiRow);main.addView(wifiBox)
        wifi.setOnCheckedChangeListener{_,checked->if(!binding)actions.wifi(checked)}
        detail.addView(link("‹ Todos los animes"){actions.group(null)},lp(bottom=14));detail.addView(detailTitle,lp(bottom=12));detail.addView(detailRows);detail.addView(detailEmpty)
    }
    fun submit(value:DownloadSnapshot){
        val next=value.group.orEmpty()
        routeChanged=route!=next
        if(route!=next){positions[route]=scrollY;route=next;restorePosition(positions[route]?:0)}
        snapshot=value;binding=true
        try{bind(value)}finally{binding=false}
    }
    fun restorePosition(value:Int){restoreScroll=value.coerceAtLeast(0);requestLayout()}
    override fun onLayout(changed:Boolean,left:Int,top:Int,right:Int,bottom:Int){
        super.onLayout(changed,left,top,right,bottom)
        val target=restoreScroll;val anchor=restoreAnchor;restoreScroll=null;restoreAnchor=null
        if(target!=null)scrollTo(0,target)
        else if(anchor!=null&&route==anchor.third&&anchor.first.isShown){val now=IntArray(2);anchor.first.getLocationOnScreen(now);scrollBy(0,now[1]-anchor.second)}
    }
    private fun refresh(){snapshot?.let{submit(it)}}
    private fun bind(s:DownloadSnapshot){
        main.visibility=if(s.group==null)VISIBLE else GONE;detail.visibility=if(s.group==null)GONE else VISIBLE
        for((key,b)in filterButtons){val selected=key==s.filter;b.isSelected=selected;b.background=outlined(if(selected)ACCENT else SURFACE,context.dp(28).toFloat());b.setTextColor(if(selected)INK else PAPER)}
        set(used,"${s.jobs.sumOf{it.bytes}.let{if(it==0L)"0 MB" else formatBytes(it)}} utilizados")
        set(available,"${formatBytes(s.free)} libres")
        val bytes=s.jobs.sumOf{it.bytes};storageBar.progress=(1000.0*bytes/(bytes+s.free).coerceAtLeast(1)).toInt().coerceIn(0,1000)
        if(wifi.isChecked!=s.wifi)wifi.isChecked=s.wifi
        val visible=s.jobs.filter{s.filter=="all"||if(s.filter=="done")it.state=="done" else it.state!="done"}
        val queued=visible.filter{it.state!="done"}.groupBy{it.slug}
        val transfers=queued.values.filter{rows->rows.any{it.state in setOf("downloading","verifying","retry","failed")}}.map{rows->
            rows.firstOrNull{it.state in setOf("downloading","verifying","retry")}?:rows.firstOrNull{it.state=="failed"}?:rows.first()
        }
        val completed=visible.filter{it.state=="done"}.groupBy{it.slug}
        val waiting=queued.filterKeys{slug->transfers.none{it.slug==slug}}
        val shape=s.filter+":"+s.group+":"+transfers.joinToString{it.key}+":"+completed.keys.joinToString()+":"+visible.filter{it.slug==s.group}.joinToString{it.key}
        val anchor=if(!routeChanged&&shape!=lastShape)visibleAnchor()else null
        val anchorRoute=route;lastShape=shape
        set(activeTitle,"${if(s.paused)"En pausa" else if(transfers.any{it.state in setOf("downloading","verifying","retry")})"Descargando" else "Pendientes"} · ${transfers.size}")
        (activeTitle.parent as View).visibility=if(transfers.isEmpty())GONE else VISIBLE
        pauseAll.visibility=if(transfers.size>1||s.paused)VISIBLE else GONE
        activeRows.visibility=if(transfers.isEmpty())GONE else VISIBLE
        pauseAll.contentDescription=if(s.paused)"Continuar todas las descargas" else "Pausar todas las descargas"
        (pauseAll.getChildAt(0)as NavGlyph).kind=if(s.paused)"play" else "pause"
        val active=transfers.map{ep->activeViews.getOrPut(ep.key){TransferRow()}.apply{bind(ep,s)}}
        reconcile(activeRows,active)
        activeViews.keys.retainAll(transfers.map{it.key}.toSet())
        (readyTitle.parent as View).visibility=if(completed.isEmpty())GONE else VISIBLE
        readyRows.visibility=if(completed.isEmpty())GONE else VISIBLE
        edit.text=if(editing)"Listo" else "Editar"
        val ready=completed.entries.mapIndexed{index,(slug,rows)->readyViews.getOrPut(slug){ReadyRow()}.apply{bind(slug,rows,index==completed.size-1)}}
        reconcile(readyRows,ready,0);readyViews.keys.retainAll(completed.keys)
        waitingTitle.visibility=if(waiting.isEmpty())GONE else VISIBLE;waitingRows.visibility=waitingTitle.visibility
        set(waitingTitle,if(s.paused)"En pausa" else "Pendientes")
        reconcile(waitingRows,waiting.entries.mapIndexed{index,(slug,rows)->waitingViews.getOrPut(slug){ReadyRow()}.apply{bind(slug,rows,index==waiting.size-1,false)}},0)
        waitingViews.keys.retainAll(waiting.keys)
        empty.visibility=if(visible.isEmpty())VISIBLE else GONE
        set(empty,if(s.owner<=0)"Inicia sesión en Inicio para guardar tus capítulos." else if(s.jobs.isEmpty())"Tus próximos episodios pueden viajar contigo. Abre un anime y pulsa «Capítulos para llevar»." else "No hay capítulos en este filtro.")
        if(s.group!=null){
            val rows=visible.filter{it.slug==s.group}.sortedBy{it.number.toDoubleOrNull()?:Double.MAX_VALUE}
            set(detailTitle,s.jobs.firstOrNull{it.slug==s.group}?.title?:"Capítulos")
            reconcile(detailRows,rows.map{ep->detailViews.getOrPut(ep.key){EpisodeRow()}.apply{bind(ep,s)}})
            detailViews.keys.retainAll(rows.map{it.key}.toSet());detailEmpty.visibility=if(rows.isEmpty())VISIBLE else GONE
        }
        if(anchor!=null){restoreAnchor=Triple(anchor.first,anchor.second,anchorRoute);requestLayout()}
    }
    private inner class TransferRow:LinearLayout(context){
        private val art=art(60,76);private val title=text("",16,true);private val meta=text("",14)
        private val progress=track(YomaColors.ACCENT);private val size=text("",14)
        private var current:Episode?=null
        private val pause=pill("Pausar"){current?.let(actions.toggle)}
        init{
            orientation=VERTICAL;setPadding(context.dp(12),context.dp(12),context.dp(12),context.dp(12));background=outlined(SURFACE,context.dp(18).toFloat())
            val heading=row();heading.addView(art,LinearLayout.LayoutParams(context.dp(60),context.dp(76)).apply{rightMargin=context.dp(10)})
            val copy=column();title.maxLines=2;title.ellipsize=TextUtils.TruncateAt.END;meta.setTextColor(MUTED);meta.maxLines=2;meta.ellipsize=TextUtils.TruncateAt.END;size.setTextColor(MUTED);size.maxLines=3;size.ellipsize=TextUtils.TruncateAt.END
            copy.addView(title);copy.addView(meta,lp(top=4));heading.addView(copy,LinearLayout.LayoutParams(0,-2,1f));heading.setOnClickListener{current?.let{actions.group(it.slug)}};addView(heading)
            addView(size,lp(top=9));addView(progress,lp(height=5,top=9))
            val controls=row();controls.addView(pause,LinearLayout.LayoutParams(0,-2,1f));controls.addView(icon("close","Cancelar descarga"){current?.let(actions.cancel)},LinearLayout.LayoutParams(context.dp(44),context.dp(44)).apply{leftMargin=context.dp(10)});addView(controls,lp(top=10))
        }
        fun bind(ep:Episode,s:DownloadSnapshot){
            current=ep;tag="download-active-${ep.key}";cover(art,ep);set(title,ep.title)
            set(meta,episodeCaption(ep));val info=DownloadPresentation.of(ep,s.paused,s.running)
            progress.visibility=if(info.progress==null)GONE else VISIBLE;progress.progress=info.progress?:0
            set(size,info.summary+if(info.error.isNotBlank())"\n${info.error}" else "")
            size.setTextColor(if(ep.state=="failed")YomaColors.ERROR else MUTED)
            set(pause,info.action);pause.isEnabled=info.actionable;pause.contentDescription="${info.action} capítulo ${ep.number} de ${ep.title}"
        }
    }
    private inner class ReadyRow:LinearLayout(context){
        private val art=art(48,48);private val title=text("",16,true);private val meta=text("",14)
        private val end=NavGlyph(context,"chevron");private var slug="";private var current:Episode?=null
        private var last=false
        private var complete=true
        private val divider=android.graphics.Paint().apply{color=YomaColors.BORDER;strokeWidth=context.dp(1).toFloat()}
        init{
            gravity=Gravity.CENTER_VERTICAL;setPadding(context.dp(12),context.dp(8),context.dp(12),context.dp(8));setWillNotDraw(false);minimumHeight=context.dp(68);isFocusable=true;isClickable=true
            addView(art,LinearLayout.LayoutParams(context.dp(48),context.dp(48)).apply{rightMargin=context.dp(12)})
            val copy=column();title.maxLines=2;title.ellipsize=TextUtils.TruncateAt.END;meta.setTextColor(MUTED);copy.addView(title);copy.addView(meta,lp(top=5));addView(copy,LinearLayout.LayoutParams(0,-2,1f));addView(end,LinearLayout.LayoutParams(context.dp(21),context.dp(21)).apply{leftMargin=context.dp(10)})
            setOnClickListener{if(editing&&complete)current?.let(actions.options)else actions.group(slug)}
        }
        override fun onDraw(canvas:android.graphics.Canvas){super.onDraw(canvas);if(!last)canvas.drawLine(context.dp(12).toFloat(),height-1f,width-context.dp(12).toFloat(),height-1f,divider)}
        fun bind(key:String,rows:List<Episode>,isLast:Boolean,done:Boolean=true){slug=key;current=rows.first();complete=done;if(last!=isLast){last=isLast;invalidate()};tag="download-${if(done)"ready" else "waiting"}-$key";cover(art,rows.first());set(title,rows.first().title);set(meta,if(done)"${rows.size} ${if(rows.size==1)"episodio" else "episodios"} · ${formatBytes(rows.sumOf{it.total})}" else "${rows.size} ${if(rows.size==1)"capítulo pendiente" else "capítulos pendientes"}");end.kind=if(editing&&complete)"more" else "chevron";contentDescription="${rows.first().title}, ${meta.text}"}
    }
    private inner class EpisodeRow:LinearLayout(context){
        private val title=text("",18,true);private val meta=text("",14);private val state=text("",14);private val error=text("",14)
        private val bar=track(YomaColors.ACCENT);private var current:Episode?=null
        private val action=pill("Reproducir"){current?.let(actions.toggle)}
        private val secondary=icon("close","Cancelar descarga"){current?.let{if(it.state=="done")actions.options(it)else actions.cancel(it)}}
        init{
            orientation=VERTICAL;setPadding(context.dp(14),context.dp(12),context.dp(14),context.dp(12));background=outlined(SURFACE,context.dp(18).toFloat())
            title.maxLines=2;title.ellipsize=TextUtils.TruncateAt.END;meta.maxLines=2;meta.setTextColor(MUTED);state.maxLines=3;error.maxLines=3;error.setTextColor(YomaColors.ERROR)
            addView(title);addView(meta,lp(top=5));addView(state,lp(top=8));addView(error,lp(top=5));addView(bar,lp(height=5,top=8))
            val buttons=row();buttons.addView(action,LinearLayout.LayoutParams(0,-2,1f));buttons.addView(secondary,LinearLayout.LayoutParams(context.dp(44),context.dp(44)).apply{leftMargin=context.dp(10)});addView(buttons,lp(top=10))
        }
        fun bind(ep:Episode,s:DownloadSnapshot){
            current=ep;tag="download-episode-${ep.key}";val info=DownloadPresentation.of(ep,s.paused,s.running)
            set(title,ep.title);set(meta,episodeCaption(ep));set(state,info.summary+(if(ep.watched)" · ✓ Visto" else ""))
            state.setTextColor(if(ep.state=="failed")YomaColors.ERROR else if(ep.state=="done")MINT else PAPER)
            set(error,info.error);error.visibility=if(info.error.isEmpty())GONE else VISIBLE
            bar.visibility=if(info.progress!=null&&ep.state!="done")VISIBLE else GONE;bar.progress=info.progress?:0
            set(action,info.action);action.isEnabled=info.actionable;action.contentDescription="${info.action} capítulo ${ep.number} de ${ep.title}"
            (secondary.getChildAt(0)as NavGlyph).kind=if(ep.state=="done")"more" else "close";secondary.contentDescription=if(ep.state=="done")"Opciones del capítulo ${ep.number}" else "Cancelar descarga del capítulo ${ep.number}"
        }
    }
    private fun reconcile(host:LinearLayout,children:List<View>,gap:Int=8){
        if(host.childCount==children.size&&children.indices.all{host.getChildAt(it)===children[it]})return
        for(i in host.childCount-1 downTo 0)if(host.getChildAt(i) !in children)host.removeViewAt(i)
        children.forEachIndexed{i,v->
            if(host.indexOfChild(v)!=i){(v.parent as? ViewGroup)?.removeView(v);host.addView(v,i,lp(top=if(i==0)0 else gap))}
            val params=v.layoutParams as LinearLayout.LayoutParams;val margin=if(i==0)0 else context.dp(gap)
            if(params.topMargin!=margin){params.topMargin=margin;v.layoutParams=params}
        }
    }
    private fun visibleAnchor():Pair<View,Int>?{
        val origin=IntArray(2);getLocationOnScreen(origin)
        return (activeViews.values+readyViews.values+waitingViews.values+detailViews.values).filter{it.isShown&&it.height>0}.map{view->val point=IntArray(2);view.getLocationOnScreen(point);view to point[1]}
            .filter{(view,y)->y+view.height>origin[1]&&y<origin[1]+height}.minByOrNull{it.second}
    }
    private fun cover(view:ImageView,ep:Episode){val url=ep.payload.optString("cover");if(view.tag!=url)CoverArt.show(view,url)}
    private fun set(view:TextView,value:String){if(view.text.toString()!=value)view.text=value}
    private fun column()=LinearLayout(context).apply{orientation=LinearLayout.VERTICAL}
    private fun row()=LinearLayout(context).apply{gravity=Gravity.CENTER_VERTICAL}
    private fun lp(height:Int=-2,top:Int=0,bottom:Int=0)=LinearLayout.LayoutParams(-1,if(height<0)height else context.dp(height)).apply{topMargin=context.dp(top);bottomMargin=context.dp(bottom)}
    private fun text(value:String,size:Int,serif:Boolean=false)=TextView(context).apply{text=value;textSize=size.toFloat();includeFontPadding=false;setTextColor(PAPER);setLineSpacing(0f,1.1f);if(serif){typeface=YomaType.title;letterSpacing=YomaType.TITLE_SPACING}}
    private fun box()=column().apply{background=outlined(SURFACE,context.dp(18).toFloat());setPadding(context.dp(14),context.dp(14),context.dp(14),context.dp(14))}
    private fun pill(value:String,click:()->Unit)=Button(context).apply{text=value;textSize=14f;includeFontPadding=false;isAllCaps=false;minWidth=0;minimumWidth=0;minHeight=context.dp(44);setPadding(context.dp(8),context.dp(9),context.dp(8),context.dp(9));background=outlined(SURFACE,context.dp(24).toFloat());setTextColor(PAPER);setOnClickListener{click()}}
    private fun link(value:String,click:()->Unit)=pill(value,click).apply{background=null;setTextColor(YomaColors.ACCENT);gravity=Gravity.END or Gravity.CENTER_VERTICAL}
    private fun icon(kind:String,name:String,click:()->Unit)=FrameLayout(context).apply{minimumWidth=context.dp(44);minimumHeight=context.dp(44);background=outlined(SURFACE,context.dp(24).toFloat());contentDescription=name;isFocusable=true;isClickable=true;addView(NavGlyph(context,kind),FrameLayout.LayoutParams(context.dp(20),context.dp(20),Gravity.CENTER));setOnClickListener{click()}}
    private fun art(width:Int,height:Int)=ImageView(context).apply{setImageResource(R.drawable.anime_brand);scaleType=ImageView.ScaleType.CENTER_CROP;background=outlined(SURFACE,context.dp(11).toFloat());clipToOutline=true;importantForAccessibility=IMPORTANT_FOR_ACCESSIBILITY_NO;minimumWidth=context.dp(width);minimumHeight=context.dp(height)}
    private fun track(color:Int)=ProgressBar(context,null,android.R.attr.progressBarStyleHorizontal).apply{
        max=1000;minimumHeight=0;setPadding(0,0,0,0)
        val layer=LayerDrawable(arrayOf(GradientDrawable().apply{setColor(YomaColors.SURFACE_HIGH);cornerRadius=context.dp(8).toFloat()},ClipDrawable(GradientDrawable().apply{setColor(color);cornerRadius=context.dp(8).toFloat()},Gravity.START,ClipDrawable.HORIZONTAL)))
        layer.setId(0,android.R.id.background);layer.setId(1,android.R.id.progress);progressDrawable=layer
        progressTintList=ColorStateList.valueOf(color);progressBackgroundTintList=ColorStateList.valueOf(YomaColors.SURFACE_HIGH)
    }
}
