// Java 17+: java scripts/GenerateAndroidMissionFixture.java <resource-directory>
// Uses the same ZipOutputStream/streaming descriptors as Android packages.
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
class GenerateAndroidMissionFixture {
    static byte[] bytes(String value) { return value.getBytes(StandardCharsets.UTF_8); }
    static byte[] zip(LinkedHashMap<String, byte[]> entries) throws Exception {
        var output = new ByteArrayOutputStream();
        try (var zip = new ZipOutputStream(output)) {
            for (var entry : entries.entrySet()) {
                var member = new ZipEntry(entry.getKey()); member.setTime(1700000000000L);
                zip.putNextEntry(member); zip.write(entry.getValue()); zip.closeEntry();
            }
        }
        return output.toByteArray();
    }
    static byte[] kml(String body) { return bytes("<kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document>"+body+"</Document></kml>"); }
    public static void main(String[] args) throws Exception {
        Path directory = Path.of(args[0]); Files.createDirectories(directory);
        var nested = new LinkedHashMap<String,byte[]>();
        nested.put("doc.kml",kml("<Folder><name>Mission</name><Placemark><name>Compound</name><MultiGeometry><LineString><coordinates>-117,34 -117.001,34.001 -117,34</coordinates></LineString><Polygon><outerBoundaryIs><LinearRing><coordinates>-117,34 -117.001,34 -117.001,34.001 -117,34</coordinates></LinearRing></outerBoundaryIs></Polygon></MultiGeometry></Placemark></Folder>"));
        var content = new LinkedHashMap<String,byte[]>();
        content.put("cot/hostile.cot",bytes("<event type=\"a-h-G\" uid=\"fixture-id\"><point lat=\"34.002\" lon=\"-117.002\"/><detail><contact callsign=\"Hostile &amp; one\"/></detail></event>"));
        content.put("route.gpx",bytes("<gpx><wpt lat=\"34\" lon=\"-117\"><name>Camp</name></wpt><trk><name>Walk</name><trkseg><trkpt lat=\"34\" lon=\"-117\"><time>1960-01-01T00:00:00Z</time></trkpt><trkpt lat=\"34.001\" lon=\"-117.001\"/></trkseg></trk></gpx>"));
        content.put("maps/nested.kmz",zip(nested));
        content.put("MANIFEST/manifest.xml",bytes("<MissionPackageManifest version=\"2\"/>"));
        byte[] mission = zip(content);
        Files.write(directory.resolve("android-mission-package.zip"),mission);
        // Reverse only the central directory: readers must retain local stream order.
        var view = java.nio.ByteBuffer.wrap(mission).order(java.nio.ByteOrder.LITTLE_ENDIAN);
        int end = mission.length - 22, cursor = view.getInt(end + 16), start = cursor;
        var records = new ArrayList<byte[]>();
        while (cursor < end) {
            int length = 46 + Short.toUnsignedInt(view.getShort(cursor+28)) + Short.toUnsignedInt(view.getShort(cursor+30)) + Short.toUnsignedInt(view.getShort(cursor+32));
            records.add(Arrays.copyOfRange(mission,cursor,cursor+length)); cursor += length;
        }
        Collections.reverse(records); byte[] reordered = mission.clone(); cursor = start;
        for (byte[] record : records) { System.arraycopy(record,0,reordered,cursor,record.length); cursor += record.length; }
        Files.write(directory.resolve("android-central-reordered.zip"),reordered);
        var bomb = new LinkedHashMap<String,byte[]>();
        bomb.put("doc.kml",kml("<!--"+" ".repeat(4096)+"-->"));
        var outer = new LinkedHashMap<String,byte[]>(); outer.put("nested.kmz",zip(bomb));
        Files.write(directory.resolve("android-nested-budget.zip"),zip(outer));
        System.out.println("Wrote mission and nested-budget fixtures to " + directory);
    }
}
