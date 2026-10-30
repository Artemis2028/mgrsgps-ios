// Independent Android ProtectedFiles/BackupCrypto wire fixtures. Java 17+.
import java.io.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
import javax.crypto.*;
import javax.crypto.spec.*;
class GenerateProtectedFileFixtures {
    static final String PASSWORD=System.getenv().getOrDefault("GRIDFIX_FIXTURE_PASSWORD","Nørth 雪 🧭");
    static byte[] zip(String[] names,byte[][] values) throws Exception {
        var bytes=new ByteArrayOutputStream();
        try(var zip=new ZipOutputStream(bytes)) {
            for(int i=0;i<names.length;i++) { zip.putNextEntry(new ZipEntry(names[i]));zip.write(values[i]);zip.closeEntry(); }
        }
        return bytes.toByteArray();
    }
    static byte[] key(byte[] salt,int rounds) throws Exception {
        var p=new PBEKeySpec(PASSWORD.toCharArray(),salt,rounds,256);
        try {return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(p).getEncoded();} finally {p.clearPassword();}
    }
    static byte[] seal(byte[] plain) throws Exception {
        byte[] salt=new byte[16],iv=new byte[12];Arrays.fill(salt,(byte)7);Arrays.fill(iv,(byte)11);
        byte[] header=ByteBuffer.allocate(44).put("MGRSGPS-ENC1".getBytes(StandardCharsets.US_ASCII)).putInt(310000).put(salt).put(iv).array();
        var c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(key(salt,310000),"AES"),new GCMParameterSpec(128,iv));c.updateAAD(header);
        var body=c.doFinal(plain);return ByteBuffer.allocate(44+body.length).put(header).put(body).array();
    }
    static byte[] open(byte[] sealed) throws Exception {
        var b=ByteBuffer.wrap(sealed);b.position(12);int rounds=b.getInt();byte[] salt=new byte[16],iv=new byte[12];b.get(salt);b.get(iv);
        var c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,new SecretKeySpec(key(salt,rounds),"AES"),new GCMParameterSpec(128,iv));c.updateAAD(sealed,0,44);
        return c.doFinal(sealed,44,sealed.length-44);
    }
    public static void main(String[] args) throws Exception {
        if(args[0].equals("--inspect")) {
            var archive=open(Files.readAllBytes(Path.of(args[1])));
            try(var zip=new ZipInputStream(new ByteArrayInputStream(archive))) {
                var entry=zip.getNextEntry();if(entry==null || entry.isDirectory()) throw new AssertionError("Missing export");
                byte[] payload=zip.readNBytes(16*1024*1024+1);
                if(payload.length>16*1024*1024 || zip.getNextEntry()!=null) throw new AssertionError("Unexpected export layout");
                System.out.println("Authenticated native Files export: "+entry.getName()+", "+payload.length+" bytes");
            }
            return;
        }
        Path root=Path.of(args[0]);Files.createDirectories(root);
        String gpx="<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" creator=\"Android fixture\"><wpt lat=\"35.1\" lon=\"-79\"><name>OP CAFÉ</name></wpt></gpx>";
        String kml="<?xml version=\"1.0\"?><kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document><Placemark><name>OP CAFÉ</name><Point><coordinates>-79,35.1,0</coordinates></Point></Placemark></Document></kml>";
        var values=new LinkedHashMap<String,byte[]>();
        values.put("gpx",gpx.getBytes(StandardCharsets.UTF_8));values.put("kml",kml.getBytes(StandardCharsets.UTF_8));
        values.put("csv","name,lat,lon\nOP CAFÉ,35.1,-79\n".getBytes(StandardCharsets.UTF_8));
        values.put("geojson","{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{\"name\":\"OP CAFÉ\"},\"geometry\":{\"type\":\"Point\",\"coordinates\":[-79,35.1]}}]}".getBytes(StandardCharsets.UTF_8));
        values.put("kmz",zip(new String[]{"doc.kml"},new byte[][]{kml.getBytes(StandardCharsets.UTF_8)}));
        values.put("atak",zip(new String[]{"MANIFEST/manifest.xml","items/point.kml"},new byte[][]{"<MissionPackageManifest version=\"2\"/>".getBytes(StandardCharsets.UTF_8),kml.getBytes(StandardCharsets.UTF_8)}));
        for(var item:values.entrySet()) {
            String format=item.getKey(),name="OP CAFÉ."+(format.equals("atak")?"zip":format),stem="protected-file-"+format;
            byte[] bytes=args.length>1 ? Files.readAllBytes(root.resolve(stem+".plain")) : item.getValue();
            if(args.length>1) {
                byte[] archive=open(Files.readAllBytes(Path.of(args[1]).resolve("swift-"+stem+".mgrsgps")));
                try(var z=new ZipInputStream(new ByteArrayInputStream(archive))) {
                    if(!name.equals(z.getNextEntry().getName()) || !Arrays.equals(bytes,z.readAllBytes()) || z.getNextEntry()!=null) throw new AssertionError(format+" Swift mismatch");
                }
            } else {
                Files.write(root.resolve(stem+".plain"),bytes);
                Files.write(root.resolve(stem+".mgrsgps"),seal(zip(new String[]{name},new byte[][]{bytes})));
            }
        }
        System.out.println(args.length>1?"Six Swift protected files authenticate/decode with Java":"Generated six independent Java ZIP/JCA protected-file fixtures");
    }
}
