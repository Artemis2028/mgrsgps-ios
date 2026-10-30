// Java 17+. Independent JCA vectors for Android BackupCrypto.kt at d6c971b.
// Uses the same PBEKeySpec/SecretKeyFactory/Cipher calls and wire layout.
import java.nio.*;
import java.nio.file.*;
import java.util.*;
import javax.crypto.*;
import javax.crypto.spec.*;

class GenerateBackupCryptoFixtures {
    static final byte[] MAGIC = "MGRSGPS-ENC1".getBytes(java.nio.charset.StandardCharsets.US_ASCII);
    static byte[] key(String password, byte[] salt, int rounds) throws Exception {
        var spec = new PBEKeySpec(password.toCharArray(),salt,rounds,256);
        try { return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded(); }
        finally { spec.clearPassword(); }
    }
    static byte[] seal(byte[] plain,String password,int rounds) throws Exception {
        byte[] salt = new byte[16], iv = new byte[12];
        for (int i=0;i<salt.length;i++) salt[i]=(byte)(i+1);
        for (int i=0;i<iv.length;i++) iv[i]=(byte)(32+i);
        byte[] header=ByteBuffer.allocate(44).put(MAGIC).putInt(rounds).put(salt).put(iv).array();
        var cipher=Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(key(password,salt,rounds),"AES"),new GCMParameterSpec(128,iv));
        cipher.updateAAD(header);
        byte[] body=cipher.doFinal(plain);
        return ByteBuffer.allocate(header.length+body.length).put(header).put(body).array();
    }
    static byte[] open(byte[] sealed,String password) throws Exception {
        var header=ByteBuffer.wrap(sealed);header.position(12);int rounds=header.getInt();
        byte[] salt=new byte[16],iv=new byte[12];header.get(salt);header.get(iv);
        var cipher=Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE,new SecretKeySpec(key(password,salt,rounds),"AES"),new GCMParameterSpec(128,iv));
        cipher.updateAAD(sealed,0,44);return cipher.doFinal(sealed,44,sealed.length-44);
    }
    public static void main(String[] args)throws Exception {
        Path directory=Path.of(args[0]);Files.createDirectories(directory);
        byte[] zip=Files.readAllBytes(Path.of(args[1]));
        String[] passwords={"correct horse","Nørth 雪 🧭","e\u0301cole-route","north\u0000south","🧭🧭🧭🧭"};
        StringBuilder json=new StringBuilder("[\n");
        for(int i=0;i<passwords.length;i++) {
            String name="jca-protected-"+i+".mgrsgps";
            int rounds=i==0?310000:100000;
            byte[] sealed=seal(zip,passwords[i],rounds);Files.write(directory.resolve(name),sealed);
            if(!Arrays.equals(zip,open(sealed,passwords[i])))throw new AssertionError("JCA self-check");
            if(i>0)json.append(",\n");
            json.append("{\"file\":\"").append(name).append("\",\"passwordBase64\":\"").append(Base64.getEncoder().encodeToString(passwords[i].getBytes(java.nio.charset.StandardCharsets.UTF_8))).append("\",\"iterations\":").append(rounds).append("}");
            if(args.length>2) {
                byte[] swift=Files.readAllBytes(Path.of(args[2]).resolve("swift-protected-"+i+".mgrsgps"));
                if(!Arrays.equals(zip,open(swift,passwords[i])))throw new AssertionError("Swift file mismatch "+i);
            }
        }
        Files.writeString(directory.resolve("backup-crypto-vectors.json"),json.append("\n]\n").toString());
        System.out.println(args.length>2?"All 5 Swift exports authenticate/decrypt with Java JCA":"Generated 5 independently verified JCA fixtures");
    }
}
