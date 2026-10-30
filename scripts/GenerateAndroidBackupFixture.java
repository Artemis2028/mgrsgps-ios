import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.zip.*;

// Android 1.0.4 schema contract, written with the same streaming ZipOutputStream
// API as Backup.kt. This is a synthetic contract fixture, not a device capture.
class GenerateAndroidBackupFixture {
    public static void main(String[] args) throws Exception {
        String manifest = """
        {"app":"GridFix","version":1,"exportedAt":1700000000000,
         "waypoints":[{"id":"contract-vertex","name":"Contract route WP 2","lat":24.4549,"lon":54.3783,"createdAt":1700000000000,"folder":"Recon","symbol":"flag","affiliation":"none","echelon":"","designation":"","kind":"wp","rotation":0,"visible":true,"sourceRouteId":"contract-route","sourceRoutePointIndex":1,"metadata":{"color":"cyan","milgpsSymbolCode":2110,"elevationMeters":12.5,"timestampMillis":1700000000000}}],
         "folders":[{"name":"Base","visible":true},{"name":"Recon","visible":false}],
         "graphics":[{"id":"contract-route","name":"Contract route","type":"route","points":[[24.4539,54.3773],[24.4549,54.3783]],"folder":"Recon","affiliation":"none","createdAt":1700000000000,"echelon":"","visible":true}],
         "settings":{"nightMode":false,"keepScreenOn":true,"mgrsDigits":6,"latLonFormat":2,"units":1,"angleUnit":1,"northRef":2,"pacePer100m":70,"face":2,"orientation":3,"declinationOverride":null,"disclaimerAccepted":true},
         "tracks":[{"id":"11111111-1111-4111-8111-111111111111","name":"Contract track","startedAt":1700000000000,"endedAt":1700000015000,"distanceM":9999,"pointCount":999,"folder":"Recon","visible":true}],
         "courseHistory":[{"name":"Contract course","points":2,"started":1700000000000,"total":1200,"splits":[500,700]}]}
        """;
        try (ZipOutputStream zip = new ZipOutputStream(Files.newOutputStream(Path.of(args[0])))) {
            write(zip, "gridfix-backup.json", manifest);
            write(zip, "tracks/11111111-1111-4111-8111-111111111111.txt", "24.4539000 54.3773000 1700000000000 12.5\n24.4549000 54.3783000 1700000015000 -32768.0\n");
        }
    }
    static void write(ZipOutputStream zip, String name, String contents) throws Exception {
        ZipEntry entry = new ZipEntry(name);
        entry.setTime(1700000000000L);
        zip.putNextEntry(entry);
        zip.write(contents.getBytes(StandardCharsets.UTF_8));
        zip.closeEntry();
    }
}
