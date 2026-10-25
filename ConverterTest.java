import java.io.*;
import java.nio.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;

/** Generated fixtures only: no downloaded or copyrighted audio is needed. */
public class ConverterTest {
    static int checks=0;
    static void check(boolean condition,String label) {
        if(!condition)throw new AssertionError(label);
        checks++;System.out.println("PASS "+label);
    }
    static byte[] concat(byte[]... chunks)throws IOException {
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        for(byte[] chunk:chunks)out.write(chunk);
        return out.toByteArray();
    }
    static byte[] little(int n){return ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(n).array();}
    static byte[] mp3(boolean id3) {
        // Two MPEG-1 Layer III frames, 128kbps, 44.1kHz, no padding.
        byte[] frames=new byte[834];
        for(int p:new int[]{0,417}) {frames[p]=(byte)0xff;frames[p+1]=(byte)0xfb;frames[p+2]=(byte)0x90;}
        if(!id3)return frames;
        byte[] tagged=new byte[844];System.arraycopy(new byte[]{'I','D','3',4,0,0,0,0,0,0},0,tagged,0,10);
        System.arraycopy(frames,0,tagged,10,frames.length);return tagged;
    }
    static int crc(byte[] data,int bits,int polynomial) {
        int v=0,top=1<<(bits-1),mask=(1<<bits)-1;
        for(byte b:data){v^=(b&255)<<(bits-8);for(int i=0;i<8;i++)v=((v<<1)^((v&top)!=0?polynomial:0))&mask;}
        return v;
    }
    static byte[] flac(int sample)throws Exception {
        byte[] streamInfo=new byte[34];ByteBuffer info=ByteBuffer.wrap(streamInfo);
        info.putShort((short)192).putShort((short)192);info.position(10);
        info.putLong((44100L<<44)|(15L<<36)|192L);
        byte[] pcm=new byte[384];for(int p=0;p<pcm.length;p+=2){pcm[p]=(byte)sample;pcm[p+1]=(byte)(sample>>8);}
        info.put(MessageDigest.getInstance("MD5").digest(pcm));
        byte[] header={(byte)0xff,(byte)0xf8,0x10,0x08,0};
        byte[] payload=concat(header,new byte[]{(byte)crc(header,8,7),0,(byte)(sample>>8),(byte)sample});
        int crc16=crc(payload,16,0x8005);
        return concat(new byte[]{'f','L','a','C',(byte)0x80,0,0,34},streamInfo,payload,new byte[]{(byte)(crc16>>8),(byte)crc16});
    }
    static byte[] ncm(byte[] audio,int allocated,int actual,int extra)throws Exception {
        byte[] key="synthetic-fixture-key".getBytes("US-ASCII");
        Cipher cipher=Cipher.getInstance("AES/ECB/PKCS5Padding");
        cipher.init(Cipher.ENCRYPT_MODE,new SecretKeySpec("hzHRAmso5kInbaxW".getBytes("US-ASCII"),"AES"));
        byte[] encodedKey=cipher.doFinal(concat("neteasecloudmusic".getBytes("US-ASCII"),key));
        for(int i=0;i<encodedKey.length;i++)encodedKey[i]^=0x64;
        int[] s=new int[256];for(int i=0;i<256;i++)s[i]=i;
        for(int i=0,j=0;i<256;i++){j=(j+s[i]+(key[i%key.length]&255))&255;int swap=s[i];s[i]=s[j];s[j]=swap;}
        byte[] encrypted=new byte[audio.length];
        for(int i=0;i<audio.length;i++){int x=(i+1)&255,y=(s[x]+x)&255;encrypted[i]=(byte)(audio[i]^s[(s[x]+s[y])&255]);}
        byte[] prefix=new byte[extra];Arrays.fill(prefix,(byte)0x42);
        return concat("CTENFDAM".getBytes("US-ASCII"),new byte[2],little(encodedKey.length),encodedKey,
            little(0),new byte[5],little(allocated),little(actual),new byte[allocated],prefix,encrypted);
    }
    static void rejects(Path root,byte[] contents,String label)throws Exception {
        Path source=root.resolve("bad-"+checks+".ncm"),out=root.resolve("reject-"+checks);
        Files.write(source,contents);
        boolean rejected=false;
        try{NcmConvert.convert(source,out);}catch(Exception expected){rejected=true;}
        check(rejected,label);
        check(!Files.exists(out),label+" produces no output directory");
    }
    public static void main(String[] args)throws Exception {
        Path root=Files.createTempDirectory("ncm-generated-tests-");
        try {
            Path out=root.resolve("output");
            for(boolean tagged:new boolean[]{false,true}) {
                byte[] audio=mp3(tagged),contents=ncm(audio,7486,0,0);
                Path source=root.resolve("synthetic-"+tagged+".ncm");Files.write(source,contents);
                Path result=NcmConvert.convert(source,out);
                check(Arrays.equals(audio,Files.readAllBytes(result)),"MP3 exact audio restoration; ID3="+tagged);
                check(Arrays.equals(contents,Files.readAllBytes(source)),"original is unchanged");
                check(result.equals(NcmConvert.convert(source,out)),"duplicate conversion reuses output");
            }
            byte[] lossless=flac(0);
            Path source=root.resolve("synthetic-flac.ncm");Files.write(source,ncm(lossless,64,64,4096));
            Path result=NcmConvert.convert(source,out);
            check(result.toString().endsWith(".flac"),"FLAC is never mislabeled MP3");
            check(Arrays.equals(lossless,Files.readAllBytes(result)),"FLAC restoration past extra prefix");
            Path other=root.resolve("nested");Files.createDirectory(other);
            Path collision=other.resolve("synthetic-flac.ncm");Files.write(collision,ncm(flac(1),0,0,0));
            Path second=NcmConvert.convert(collision,out);
            check(!result.equals(second),"same-name different audio gets a separate path");
            check(Arrays.equals(lossless,Files.readAllBytes(result)),"existing audio is never overwritten");
            byte[] corrupt=flac(0);corrupt[corrupt.length-1]^=1;
            rejects(root,ncm(corrupt,0,0,0),"bad FLAC CRC is rejected");
            rejects(root,new byte[]{1,2,3},"truncated file is rejected");
            byte[] truncated=Arrays.copyOf(mp3(false),800);
            rejects(root,ncm(truncated,0,0,0),"truncated MP3 frame is rejected");
            byte[] wrongSamples=flac(0);wrongSamples[25]++;
            rejects(root,ncm(wrongSamples,0,0,0),"FLAC sample-count mismatch is rejected");
            byte[] invalidLength=ncm(mp3(false),0,0,0);
            Arrays.fill(invalidLength,10,14,(byte)0xff);
            rejects(root,invalidLength,"negative block length is rejected");
            System.out.println("All "+checks+" checks passed. Fixtures are synthetic.");
        } finally {
            try(java.util.stream.Stream<Path> paths=Files.walk(root)){
                for(Path p:(Iterable<Path>)paths.sorted(Comparator.reverseOrder())::iterator)Files.deleteIfExists(p);
            }
        }
    }
}
