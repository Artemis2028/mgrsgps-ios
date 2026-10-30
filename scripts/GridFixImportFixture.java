// Reproduce InterchangeTests identity fixture with Java 17+ single-file execution.
// Field order: Android release/1.1.0 482b417 ImportCoordinator.fingerprint;
// track null-altitude sentinel: TrackRepository.NO_ALTITUDE (-32768).
import java.io.*;import java.security.*;import java.util.*;
class GridFixImportFixture {
 static void str(DataOutputStream out,String value)throws Exception {byte[] b=value.getBytes(java.nio.charset.StandardCharsets.UTF_8);out.writeInt(b.length);out.write(b);}
 static void point(DataOutputStream out,double lat,double lon)throws Exception {out.writeDouble(lat);out.writeDouble(lon);}
 public static void main(String[] args)throws Exception {
  ByteArrayOutputStream bytes=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(bytes);
  str(out,"gridfix-import-v1");out.writeInt(2);
  for(String[] w:List.of(new String[]{"One","Patrol"},new String[]{"Two","PATROL"})) {
   str(out,w[0]);point(out,34,-117);str(out,w[1]);str(out,"flag");str(out,"none");str(out,"");str(out,"");str(out,"wp");out.writeFloat(0);out.writeBoolean(false);
  }
  out.writeInt(1);str(out,"Route");str(out,"Patrol");out.writeInt(2);point(out,34,-117);point(out,34.1,-117.1);
  out.writeInt(1);str(out,"Area");str(out,"Patrol");out.writeInt(3);point(out,34,-117);point(out,34.1,-117.1);point(out,34.2,-117);
  out.writeInt(1);str(out,"Track");out.writeInt(2);
  for(double[] p:List.of(new double[]{34,-117},new double[]{34.1,-117.1})) {point(out,p[0],p[1]);out.writeLong(0);out.writeDouble(-32768);}
  String hash=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes.toByteArray()));System.out.println(hash);
  for(String kind:List.of("waypoint","line","area","track")) for(int i=0;i<(kind.equals("waypoint")?2:1);i++) System.out.println(kind+" "+i+" "+UUID.nameUUIDFromBytes(("gridfix-import-v1:"+hash+":"+kind+":"+i).getBytes(java.nio.charset.StandardCharsets.UTF_8)));
 }
}
