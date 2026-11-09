package app.yomatv.mobile

import app.yomashi.reader.R
import app.yomashi.reader.BuildConfig

import android.app.Dialog
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.*

data class EpisodeChoice(val id: Long,val title: String,val seen: Boolean,val current: Boolean,val playable: Boolean=true)

/** Stable episode IDs, with independent playback and completion touch targets. */
class EpisodePicker(private val context: Context,initial: List<EpisodeChoice>,open:(EpisodeChoice)->Unit,mark:(EpisodeChoice,Boolean)->Boolean) {
    private val rows=initial.toMutableList()
    val list=ListView(context).apply{divider=null;dividerHeight=context.dp(8);setPadding(context.dp(12),context.dp(8),context.dp(12),context.dp(8));clipToPadding=false}
    private val adapter=object:BaseAdapter(){
        override fun getCount()=rows.size
        override fun getItem(position:Int)=rows[position]
        override fun getItemId(position:Int)=rows[position].id
        override fun hasStableIds()=true
        override fun getView(position:Int,convertView:View?,parent:ViewGroup):View {
            val row=(convertView as? ChoiceRow)?:ChoiceRow(context)
            val choice=rows[position]
            row.bind(choice,{open(choice);dialog.dismiss()}){value->
                if(mark(choice,value)){rows[position]=choice.copy(seen=value);notifyDataSetChanged()}else row.bindChecked(choice.seen)
            }
            return row
        }
    }
    val dialog=Dialog(context)
    init{
        dialog.requestWindowFeature(android.view.Window.FEATURE_NO_TITLE)
        list.adapter=adapter
        val body=LinearLayout(context).apply{orientation=LinearLayout.VERTICAL;setPadding(context.dp(16),context.dp(16),context.dp(16),context.dp(16));background=outlined(INK,context.dp(24).toFloat())}
        body.addView(TextView(context).apply{text="Episodios";textSize=24f;setTextColor(PAPER);includeFontPadding=false;setPadding(context.dp(8),context.dp(4),context.dp(8),context.dp(12))})
        val maxList=((context.resources.displayMetrics.heightPixels*.78).toInt()-context.dp(140)).coerceAtLeast(context.dp(72))
        body.addView(list,LinearLayout.LayoutParams(-1,minOf(context.dp(100)*rows.size.coerceAtLeast(1),maxList)))
        body.addView(Button(context).apply{text="Cerrar";isAllCaps=false;textSize=14f;setTextColor(PAPER);includeFontPadding=false;minimumHeight=context.dp(48);background=outlined(SURFACE,context.dp(24).toFloat());setOnClickListener{dialog.dismiss()}},LinearLayout.LayoutParams(-1,-2).apply{topMargin=context.dp(12)})
        dialog.setContentView(body)
    }
    fun show(){dialog.show();dialog.window?.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.TRANSPARENT));dialog.window?.setLayout(minOf(context.resources.displayMetrics.widthPixels-context.dp(32),context.dp(640)),-2);val current=rows.indexOfFirst{it.current};if(current>=0)list.setSelection(current)}
    private class ChoiceRow(context:Context):LinearLayout(context){
        private var binding=false
        private val title=TextView(context).apply{textSize=16f;setTextColor(PAPER);maxLines=2;ellipsize=TextUtils.TruncateAt.END;includeFontPadding=false}
        private val actual=TextView(context).apply{text="Actual";textSize=14f;setTextColor(ACCENT);includeFontPadding=false}
        private val copy=LinearLayout(context).apply{orientation=VERTICAL;gravity=Gravity.CENTER_VERTICAL;minimumHeight=context.dp(52);addView(title);addView(actual,LayoutParams(-2,-2).apply{topMargin=context.dp(6)})}
        private val check=CheckBox(context).apply{textSize=14f;setTextColor(PAPER);includeFontPadding=false;minimumHeight=context.dp(48);maxWidth=context.dp(122);buttonTintList=android.content.res.ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked),intArrayOf()),intArrayOf(MINT,MUTED))}
        init{gravity=Gravity.CENTER_VERTICAL;setPadding(context.dp(12),context.dp(10),context.dp(8),context.dp(10));addView(copy,LayoutParams(0,-2,1f));addView(check,LayoutParams(context.dp(122),-2).apply{leftMargin=context.dp(10)})}
        fun bindChecked(value:Boolean){binding=true;check.isChecked=value;check.text=if(value)"Visto" else "Marcar visto";binding=false}
        fun bind(choice:EpisodeChoice,open:()->Unit,mark:(Boolean)->Unit){
            tag="episode-choice-${choice.id}";title.text=choice.title;actual.tag="episode-current-${choice.id}";actual.visibility=if(choice.current)VISIBLE else GONE
            background=outlined(if(choice.current)0xff30212b.toInt() else SURFACE,context.dp(14).toFloat())
            check.setOnCheckedChangeListener(null);bindChecked(choice.seen);check.tag="episode-mark-${choice.id}";check.contentDescription="${if(choice.seen)"Quitar de vistos" else "Marcar como visto"}: ${choice.title}"
            check.setOnCheckedChangeListener{_,value->if(!binding)mark(value)}
            copy.isEnabled=choice.playable;copy.isClickable=choice.playable;copy.isFocusable=true;copy.contentDescription="${choice.title}${if(choice.current)" · Actual" else ""}${if(choice.playable)" · Reproducir" else " · Todavía no está descargado"}";copy.setOnClickListener{if(choice.playable)open()}
        }
    }
}
