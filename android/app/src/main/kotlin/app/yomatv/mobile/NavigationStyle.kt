package app.yomatv.mobile

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView

/** A tab has its own text rules; body-label padding must never move its caption. */
class NavigationTab(context: Context, key: String, name: String): LinearLayout(context) {
    init {
        orientation=VERTICAL;gravity=Gravity.TOP or Gravity.CENTER_HORIZONTAL
        minimumHeight=context.dp(64);setPadding(context.dp(3),context.dp(6),context.dp(3),context.dp(6))
        contentDescription=name;isFocusable=true;isClickable=true;tag=key
        addView(NavGlyph(context,key),LayoutParams(context.dp(24),context.dp(24)))
        addView(TextView(context).apply {
            text=name;textSize=14f;setTextColor(PAPER);includeFontPadding=false
            gravity=Gravity.CENTER;textAlignment=View.TEXT_ALIGNMENT_GRAVITY
            maxLines=2;ellipsize=android.text.TextUtils.TruncateAt.END;setLineSpacing(0f,1.1f)
            importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO
        },LayoutParams(LayoutParams.MATCH_PARENT,LayoutParams.WRAP_CONTENT).apply{topMargin=context.dp(5)})
    }
}

fun outlined(color: Int, radius: Float) = GradientDrawable().apply {
    setColor(color); cornerRadius=radius; setStroke(1,0xff393449.toInt())
}

/** Vector icons stay sharp and do not depend on the device's font or emoji set. */
class NavGlyph(context: Context, kind: String): View(context) {
    var kind:String=kind
        set(value){if(field!=value){field=value;invalidate()}}
    var tint: Int = PAPER
        set(value){field=value;invalidate()}
    private val pen=Paint(Paint.ANTI_ALIAS_FLAG).apply {style=Paint.Style.STROKE;strokeWidth=1.6f;strokeCap=Paint.Cap.ROUND;strokeJoin=Paint.Join.ROUND}
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas);canvas.save();canvas.scale(width/24f,height/24f);pen.color=tint
        val path=Path()
        when(kind){
            "pause"->{canvas.drawLine(8f,5f,8f,19f,pen);canvas.drawLine(16f,5f,16f,19f,pen)}
            "play"->{path.moveTo(8f,4f);path.lineTo(20f,12f);path.lineTo(8f,20f);path.close();canvas.drawPath(path,pen)}
            "close"->{canvas.drawLine(6f,6f,18f,18f,pen);canvas.drawLine(18f,6f,6f,18f,pen)}
            "back"->{path.moveTo(14f,5f);path.lineTo(7f,12f);path.lineTo(14f,19f);canvas.drawPath(path,pen)}
            "wifi"->{canvas.drawArc(2f,5f,22f,23f,222f,96f,false,pen);canvas.drawArc(6f,10f,18f,22f,224f,92f,false,pen);canvas.drawCircle(12f,19f,1f,pen)}
            "notifications"->{path.moveTo(5f,17f);path.lineTo(7f,14f);path.lineTo(7f,9f);path.cubicTo(7f,2f,17f,2f,17f,9f);path.lineTo(17f,14f);path.lineTo(19f,17f);path.close();canvas.drawPath(path,pen);canvas.drawLine(10f,21f,14f,21f,pen)}
            "account"->{canvas.drawCircle(12f,8f,3f,pen);path.moveTo(5f,21f);path.cubicTo(5f,12f,19f,12f,19f,21f);canvas.drawPath(path,pen)}
            "catalog"->{path.moveTo(3f,10f);path.lineTo(12f,3f);path.lineTo(21f,10f);path.lineTo(21f,21f);path.lineTo(15f,21f);path.lineTo(15f,14f);path.lineTo(9f,14f);path.lineTo(9f,21f);path.lineTo(3f,21f);path.close();canvas.drawPath(path,pen)}
            "schedule"->{canvas.drawRoundRect(3f,5f,21f,21f,2f,2f,pen);canvas.drawLine(3f,10f,21f,10f,pen);canvas.drawLine(8f,3f,8f,7f,pen);canvas.drawLine(16f,3f,16f,7f,pen)}
            "downloads"->{path.moveTo(12f,3f);path.lineTo(12f,16f);path.moveTo(7f,11f);path.lineTo(12f,16f);path.lineTo(17f,11f);path.moveTo(3f,16f);path.lineTo(3f,21f);path.lineTo(21f,21f);path.lineTo(21f,16f);canvas.drawPath(path,pen)}
            "library"->{canvas.drawRoundRect(3f,3f,8f,21f,1f,1f,pen);canvas.drawRoundRect(11f,3f,16f,21f,1f,1f,pen);path.moveTo(18f,4f);path.lineTo(22f,20f);path.moveTo(4f,7f);path.lineTo(7f,7f);path.moveTo(12f,7f);path.lineTo(15f,7f);canvas.drawPath(path,pen)}
            "history"->{canvas.drawArc(4f,4f,21f,21f,210f,300f,false,pen);path.moveTo(3f,4f);path.lineTo(3f,10f);path.lineTo(9f,10f);path.moveTo(12f,7f);path.lineTo(12f,13f);path.lineTo(16f,15f);canvas.drawPath(path,pen)}
            "mal"->{canvas.drawRoundRect(3f,3f,21f,21f,3f,3f,pen);path.moveTo(6f,8f);path.lineTo(8f,10f);path.lineTo(11f,6f);path.moveTo(14f,8f);path.lineTo(18f,8f);path.moveTo(6f,15f);path.lineTo(8f,17f);path.lineTo(11f,13f);path.moveTo(14f,15f);path.lineTo(18f,15f);canvas.drawPath(path,pen)}
            "favorites"->{path.moveTo(12f,2.5f);path.lineTo(15f,8.5f);path.lineTo(21.5f,9.5f);path.lineTo(16.8f,14.2f);path.lineTo(18f,21f);path.lineTo(12f,17.8f);path.lineTo(6f,21f);path.lineTo(7.2f,14.2f);path.lineTo(2.5f,9.5f);path.lineTo(9f,8.5f);path.close();canvas.drawPath(path,pen)}
            "collections"->{canvas.drawRoundRect(3f,8f,18f,21f,2f,2f,pen);path.moveTo(6f,5f);path.lineTo(20f,5f);path.lineTo(20f,18f);path.moveTo(9f,2f);path.lineTo(23f,2f);path.lineTo(23f,15f);canvas.drawPath(path,pen)}
            "appearance"->{path.moveTo(12f,3f);path.cubicTo(1f,3f,0f,20f,12f,21f);path.cubicTo(16f,21f,16f,18f,14f,16f);path.cubicTo(12f,13f,21f,17f,21f,11f);path.cubicTo(21f,6f,17f,3f,12f,3f);canvas.drawPath(path,pen);for(point in listOf(7f to 9f,11f to 6f,16f to 8f,6f to 14f))canvas.drawCircle(point.first,point.second,1f,pen)}
            "storage"->{canvas.drawRoundRect(3f,13f,21f,21f,2f,2f,pen);path.moveTo(3f,15f);path.lineTo(6f,4f);path.lineTo(18f,4f);path.lineTo(21f,15f);path.moveTo(15f,17f);path.lineTo(15.1f,17f);path.moveTo(18f,17f);path.lineTo(18.1f,17f);canvas.drawPath(path,pen)}
            "radio"->{path.moveTo(9f,17f);path.lineTo(9f,5f);path.lineTo(20f,3f);path.lineTo(20f,15f);path.moveTo(9f,9f);path.lineTo(20f,7f);canvas.drawPath(path,pen);canvas.drawOval(3f,15f,9f,20f,pen);canvas.drawOval(14f,13f,20f,18f,pen)}
            "stats"->{canvas.drawLine(3f,21f,22f,21f,pen);canvas.drawRoundRect(4f,12f,8f,21f,1f,1f,pen);canvas.drawRoundRect(11f,4f,15f,21f,1f,1f,pen);canvas.drawRoundRect(18f,8f,22f,21f,1f,1f,pen)}
            "queue"->{canvas.drawRoundRect(2f,3f,22f,17f,2f,2f,pen);path.moveTo(8f,21f);path.lineTo(16f,21f);path.moveTo(12f,17f);path.lineTo(12f,21f);path.moveTo(6f,10f);path.lineTo(17f,10f);path.moveTo(13f,6f);path.lineTo(17f,10f);path.lineTo(13f,14f);canvas.drawPath(path,pen)}
            "sync"->{canvas.drawArc(3f,3f,21f,21f,210f,145f,false,pen);canvas.drawArc(3f,3f,21f,21f,30f,145f,false,pen);path.moveTo(16f,8f);path.lineTo(21f,11f);path.lineTo(22f,5f);path.moveTo(8f,16f);path.lineTo(3f,13f);path.lineTo(2f,19f);canvas.drawPath(path,pen)}
            "chevron"->{path.moveTo(9f,5f);path.lineTo(16f,12f);path.lineTo(9f,19f);canvas.drawPath(path,pen)}
            else->{pen.style=Paint.Style.FILL;for(x in listOf(5f,12f,19f))canvas.drawCircle(x,12f,1.6f,pen);pen.style=Paint.Style.STROKE}
        }
        canvas.restore()
    }
}
