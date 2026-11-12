package dev.gamelingo.tv

object LayoutPolicy {
    fun anchor(width: Float,height: Float,boxWidth: Float,newestHeight: Float,margin: Float,x: Float,y: Float): Pair<Float,Float> {
        val half=boxWidth/2
        val cx=(width/2+x).coerceIn(margin+half,width-margin-half)
        val bottom=if(newestHeight+2*margin>height) height-margin
            else (height*.92f+y).coerceIn(margin+newestHeight,height-margin)
        return Pair(cx,bottom)
    }
    fun retained(heights: List<Float>,budget: Float,spacing: Float): Int {
        var count=0;var used=0f
        for(h in heights.asReversed()) {
            if(count>0 && used+h>budget) break
            used+=h+spacing;count++
        }
        return count
    }
}

