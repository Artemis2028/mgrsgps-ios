// Compile with Android's unmodified coords/SunMoon.kt at 482b417.
// The output is the primary-source parity fixture consumed by Swift tests.
import app.gridfix.android.coords.SunMoon
import java.util.Locale
import java.util.TimeZone

private data class Case(val name: String,val y: Int,val m: Int,val d: Int,val lat: Double,val lon: Double,val zone: String)
private fun numbers(values: List<Double?>): String = values.joinToString(",", "[", "]") { it?.let { String.format(Locale.US,"%.12f",it) } ?: "null" }
private fun strings(values: List<String>): String = values.joinToString(",", "[", "]") { "\"$it\"" }
fun main() {
    val cases = listOf(
        Case("Abu Dhabi summer",2026,6,21,24.4539,54.3773,"Asia/Dubai"),
        Case("Kuwait autumn",2026,10,25,29.3759,47.9774,"Asia/Kuwait"),
        Case("New York spring transition",2026,3,8,40.7128,-74.006,"America/New_York"),
        Case("New York autumn transition",2026,11,1,40.7128,-74.006,"America/New_York"),
        Case("Longyearbyen summer",2026,6,21,78.22,15.65,"Arctic/Longyearbyen"),
        Case("Longyearbyen winter",2026,12,21,78.22,15.65,"Arctic/Longyearbyen"),
        Case("East dateline",2026,10,25,1.0,179.99,"Pacific/Tarawa"),
        Case("West dateline",2026,10,25,1.0,-179.99,"Pacific/Pago_Pago")
    )
    println(cases.joinToString(",\n","[\n","\n]") { c ->
        TimeZone.setDefault(TimeZone.getTimeZone(c.zone))
        val sun = SunMoon.sunTimes(c.y,c.m,c.d,c.lat,c.lon)
        val moon = SunMoon.moonInfo(c.y,c.m,c.d,c.lat,c.lon)
        val events = listOf(sun.bmnt,sun.civilDawn,sun.sunrise,sun.sunset,sun.civilDusk,sun.eent)
        """{"name":"${c.name}","y":${c.y},"m":${c.m},"d":${c.d},"lat":${c.lat},"lon":${c.lon},"zone":"${c.zone}","sunUT":${numbers(events)},"local":${strings(events.map { SunMoon.formatLocal(it,c.y,c.m,c.d) })},"zulu":${strings(events.map { SunMoon.formatZulu(it) })},"phase":"${moon.phaseName}","illumination":${moon.illuminationPct},"rises":${numbers(moon.rises)},"sets":${numbers(moon.sets)}}"""
    })
}
