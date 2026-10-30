import java.nio.file.*;
import java.util.zip.*;
import java.io.*;
// Independent JDK ZipFile verification; no app ZIP implementation is used.
class VerifyZip64Fixtures {
 public static void main(String[] paths) throws Exception {
  if(paths.length==0) throw new IllegalArgumentException("Pass ZIP fixture paths to verify");
  for(String path: paths) {
   int files=0;
   try(ZipFile zip=new ZipFile(path)) {
    var entries=zip.entries();
    while(entries.hasMoreElements()) {
     var entry=entries.nextElement();
     try(var input=zip.getInputStream(entry)) {
      var bytes=input.readAllBytes(); var crc=new CRC32(); crc.update(bytes);
      if(bytes.length!=entry.getSize() || crc.getValue()!=entry.getCrc()) throw new IOException("CRC/size mismatch "+entry.getName());
      files++;
     }
    }
   }
   System.out.println(Path.of(path).getFileName()+": Java ZipFile verified "+files+" members");
  }
 }
}
