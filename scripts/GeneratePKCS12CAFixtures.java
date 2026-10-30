import java.nio.file.*;
import java.security.*;
import java.security.cert.*;
import java.io.*;
class GridFixCAFixtures {
  public static void main(String[] args) throws Exception {
    Path root=Path.of(args[0]);
    var certificate=CertificateFactory.getInstance("X.509").generateCertificate(new ByteArrayInputStream(Files.readAllBytes(root.resolve("p12-ca-expected.cer"))));
    String[][] variants={
      {"jca-aes-sha1-prf","PBEWithHmacSHA1AndAES_256","HmacPBESHA256","fixture-password"},
      {"jca-aes-sha512-prf","PBEWithHmacSHA512AndAES_256","HmacPBESHA512","fixture-password"},
      {"jca-rc2-empty","PBEWithSHA1AndRC2_40","HmacPBESHA1",""}
    };
    for (var variant:variants) {
      Security.setProperty("keystore.pkcs12.certProtectionAlgorithm",variant[1]);
      Security.setProperty("keystore.pkcs12.macAlgorithm",variant[2]);
      Security.setProperty("keystore.pkcs12.certPbeIterationCount","2048");
      Security.setProperty("keystore.pkcs12.macIterationCount","2048");
      var store=KeyStore.getInstance("PKCS12"); var password=variant[3].toCharArray();
      store.load(null,password); store.setCertificateEntry("synthetic-ca",certificate);
      try(var stream=Files.newOutputStream(root.resolve("p12-ca-"+variant[0]+".p12"))) {store.store(stream,password);}
    }
  }
}
