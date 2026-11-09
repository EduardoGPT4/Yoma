package app.yomatv.mobile

import android.content.Context
import android.net.Uri
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView

/** The image overlays the initial, so missing or failed images need no extra UI. */
class AccountAvatar(context:Context,private val load:(ImageView,String)->Unit=CoverArt::show):FrameLayout(context) {
    private val initial=TextView(context).apply {
        gravity=Gravity.CENTER;textSize=19f;includeFontPadding=false;setTextColor(0xffc7b8da.toInt())
        importantForAccessibility=IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val photo=ImageView(context).apply {
        scaleType=ImageView.ScaleType.CENTER_CROP;importantForAccessibility=IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private var boundUrl=""
    init {
        background=background(SURFACE,context.dp(40).toFloat());clipToOutline=true
        addView(initial,LayoutParams(-1,-1));addView(photo,LayoutParams(-1,-1));bind("","")
    }
    fun bind(name:String,url:String) {
        initial.text=name.trim().take(1).uppercase().ifBlank{"S"}
        val safe=picture(url)
        if(boundUrl==safe)return
        boundUrl=safe;photo.tag=null;photo.setImageDrawable(null)
        if(safe.isNotBlank())load(photo,safe)
    }
    companion object {
        fun picture(value:String):String {
            if(value.length>2048||value.any{it.isWhitespace()||it=='\\'||it.code<32})return ""
            val uri=runCatching{Uri.parse(value)}.getOrNull()?:return ""
            return value.takeIf{uri.scheme=="https"&&uri.host=="cdn.myanimelist.net"&&uri.userInfo==null&&uri.port in setOf(-1,443)&&uri.fragment==null}.orEmpty()
        }
    }
}
