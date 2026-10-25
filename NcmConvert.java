import java.io.*;
import java.nio.*;
import java.nio.file.*;
import java.util.*;
import javax.crypto.*;
import javax.crypto.spec.*;
import javax.swing.*;

public class NcmConvert {
    static byte[] decrypt(byte[] data, String hex) throws Exception {
        byte[] key=new byte[16];
        for(int i=0;i<16;i++) key[i]=(byte)Integer.parseInt(hex.substring(i*2,i*2+2),16);
        Cipher c=Cipher.getInstance("AES/ECB/PKCS5Padding");
        c.init(Cipher.DECRYPT_MODE,new SecretKeySpec(key,"AES"));
        return c.doFinal(data);
    }
    static int length(ByteBuffer b) throws IOException {
        if(b.remaining()<4) throw new IOException("文件头不完整");
        int n=b.getInt();
        if(n<0 || n>b.remaining()) throw new IOException("文件长度异常或文件不完整");
        return n;
    }
    static byte[] block(ByteBuffer b) throws IOException {
        byte[] v=new byte[length(b)]; b.get(v); return v;
    }
    static Path convert(Path source) throws Exception {
        return convert(source,source.toAbsolutePath().getParent().resolve("转换结果"));
    }
    static Path convert(Path source, Path dir) throws Exception {
        long size=Files.size(source);
        if(size>512L*1024*1024) throw new IOException("文件超过512MB，暂不支持");
        byte[] raw=Files.readAllBytes(source);
        if(raw.length<14 || !new String(raw,0,8,"US-ASCII").equals("CTENFDAM"))
            throw new IOException("不是有效的NCM文件");
        ByteBuffer b=ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN); b.position(10);
        byte[] encryptedKey=block(b);
        for(int i=0;i<encryptedKey.length;i++) encryptedKey[i]^=0x64;
        byte[] fullKey=decrypt(encryptedKey,"687a4852416d736f356b496e62617857");
        if(fullKey.length<=17 || !new String(fullKey,0,17,"US-ASCII").equals("neteasecloudmusic"))
            throw new IOException("不支持的NCM密钥格式");
        byte[] key=Arrays.copyOfRange(fullKey,17,fullKey.length);
        block(b); // Metadata is unnecessary for restoring the original audio stream.
        if(b.remaining()<13) throw new IOException("封面区不完整");
        b.position(b.position()+5); // CRC and reserved byte
        int allocated=b.getInt(), actual=b.getInt();
        if(allocated<0 || actual<0 || actual>allocated || allocated>b.remaining())
            throw new IOException("封面区长度异常");
        b.position(b.position()+allocated); // Skip the entire allocation, including padding.
        int[] box=new int[256];
        for(int i=0;i<256;i++) box[i]=i;
        for(int i=0,j=0;i<256;i++) {
            j=(j+box[i]+(key[i%key.length]&255))&255;
            int t=box[i]; box[i]=box[j]; box[j]=t;
        }
        byte[] stream=new byte[256];
        for(int k=0;k<256;k++) {
            int i=(k+1)&255,j=(box[i]+i)&255;
            stream[k]=(byte)box[(box[i]+box[j])&255];
        }
        int start=b.position();
        // A recognizable but damaged stream must fail validation below. Never
        // silently crop it by searching for a later frame that happens to work.
        if(!audioMarker(raw,start,stream)) {
            int found=-1;
            for(int pos=start+1;pos+4<=raw.length && pos-start<=16*1024*1024;pos++) {
                int a=(raw[pos]^stream[0])&255,c=(raw[pos+1]^stream[1])&255;
                if(!((a=='f' && c=='L' && (byte)(raw[pos+2]^stream[2])=='a' && (byte)(raw[pos+3]^stream[3])=='C') ||
                     (a=='I' && c=='D' && (byte)(raw[pos+2]^stream[2])=='3') ||
                     (a==255 && (c&224)==224 && mp3Prefix(raw,pos,stream)))) continue;
                if(validStart(raw,pos,stream)) {found=pos;break;}
            }
            if(found<0) throw new IOException("无法定位有效音频，可能是不支持的格式或文件损坏");
            System.out.println("兼容修复：跳过额外数据 "+(found-start)+" 字节");
            b.position(found);
        }
        byte[] audio=new byte[b.remaining()]; b.get(audio);
        for(int i=0;i<audio.length;i++) audio[i]^=stream[i&255];
        String format;
        if(audio.length>=4 && audio[0]=='f' && audio[1]=='L' && audio[2]=='a' && audio[3]=='C') {
            validateFlac(audio); format="flac";
        }
        else if(audio.length>=4 && ((audio[0]=='I' && audio[1]=='D' && audio[2]=='3') ||
                ((audio[0]&255)==255 && (audio[1]&224)==224))) {
            validateMp3(audio); format="mp3";
        } else throw new IOException("解码后未识别到MP3或FLAC，可能是新格式或损坏文件");
        Files.createDirectories(dir);
        String base=source.getFileName().toString().replaceFirst("(?i)\\.ncm$","");
        Path target=dir.resolve(outputName(base,"."+format));
        for(int i=2;Files.exists(target);i++) {
            if(sameAudio(target,audio)) return target;
            target=dir.resolve(outputName(base," ("+i+")."+format));
        }
        Path temp=Files.createTempFile(dir,".ncm-converting-",".tmp");
        try {
            Files.write(temp,audio);
            Files.move(temp,target); // A concurrent destination is never replaced.
        } finally {Files.deleteIfExists(temp);}
        return target;
    }
    static String outputName(String base,String suffix) throws IOException {
        if(base.isEmpty())base="audio";
        int budget=255-suffix.getBytes("UTF-8").length,bytes=0,end=0;
        while(end<base.length()) {
            int cp=base.codePointAt(end),n=cp<=127?1:cp<=2047?2:cp<=65535?3:4;
            if(bytes+n>budget)break;
            bytes+=n;end+=Character.charCount(cp);
        }
        return base.substring(0,end)+suffix;
    }
    static int decodedHeader(byte[] raw,int pos,byte[] stream,int offset) {
        int h=0;for(int i=0;i<4;i++)h=(h<<8)|((raw[pos+offset+i]^stream[(offset+i)&255])&255);return h;
    }
    static boolean audioMarker(byte[] raw,int pos,byte[] stream) {
        if(pos<0 || pos+4>raw.length)return false;
        int h=decodedHeader(raw,pos,stream,0);
        return h==0x664c6143 || (h>>>8)==0x494433 || (h>>>21)==2047;
    }
    static boolean mp3Prefix(byte[] raw,int pos,byte[] stream) {
        int n=mp3FrameLength(decodedHeader(raw,pos,stream,0));
        if(n<4 || pos+n>raw.length)return false;
        if(pos+n==raw.length)return true;
        if(pos+n+4>raw.length)return false;
        int next=decodedHeader(raw,pos,stream,n);
        return mp3FrameLength(next)>0 || (next>>>8)==0x544147 || next==0x41504554 || (next>>>8)==0x494433;
    }
    static boolean sameAudio(Path p,byte[] audio) throws IOException {
        if(!Files.isRegularFile(p) || Files.size(p)!=audio.length) return false;
        try(InputStream in=Files.newInputStream(p)) {
            byte[] chunk=new byte[65536];int offset=0,n;
            while((n=in.read(chunk))!=-1) {
                for(int i=0;i<n;i++) if(chunk[i]!=audio[offset+i]) return false;
                offset+=n;
            }
            return offset==audio.length;
        }
    }
    static boolean validStart(byte[] raw,int pos,byte[] stream) {
        if(pos+4>raw.length) return false;
        int a=(raw[pos]^stream[0])&255,c=(raw[pos+1]^stream[1])&255;
        boolean flac=a=='f' && c=='L' && (byte)(raw[pos+2]^stream[2])=='a' && (byte)(raw[pos+3]^stream[3])=='C';
        boolean mp3=(a=='I' && c=='D' && (byte)(raw[pos+2]^stream[2])=='3') || (a==255 && (c&224)==224);
        if(!flac && !mp3) return false;
        byte[] decoded=Arrays.copyOfRange(raw,pos,raw.length);
        for(int i=0;i<decoded.length;i++) decoded[i]^=stream[i&255];
        try {if(flac) validateFlac(decoded);else validateMp3(decoded);return true;}
        catch(IOException e) {return false;}
    }
    static void validateFlac(byte[] a) throws IOException {
        if(a.length<46 || (a[4]&127)!=0 || a[5]!=0 || a[6]!=0 || a[7]!=34)
            throw new IOException("FLAC STREAMINFO头异常");
        long packed=0; for(int i=18;i<26;i++) packed=(packed<<8)|(a[i]&255);
        long hz=packed>>>44, samples=packed&0xfffffffffL;
        if(hz<1 || hz>1048575) throw new IOException("FLAC采样信息异常");
        int p=4;
        while(true) {
            if(p+4>a.length) throw new IOException("FLAC元数据不完整");
            boolean last=(a[p]&128)!=0;
            int n=(a[p+1]&255)<<16|(a[p+2]&255)<<8|(a[p+3]&255);
            if(n>a.length-p-4) throw new IOException("FLAC元数据长度异常");
            p+=4+n;if(last)break;
        }
        if(p+2>=a.length || (a[p]&255)!=255 || (a[p+1]&254)!=248)
            throw new IOException("FLAC音频帧起点异常");
        int blockSize=flacBlockSize(a,p),crc=0,frames=0;long total=0;
        if(blockSize<1) throw new IOException("FLAC帧头校验失败");
        for(int i=p;i<a.length;i++) {
            crc=((crc<<8)^FLAC_CRC[((crc>>>8)^(a[i]&255))&255])&65535;
            if(crc==0 && i+2<a.length && (a[i+1]&255)==255 && (a[i+2]&254)==248) {
                int next=flacBlockSize(a,i+1);
                if(next>0){total+=blockSize;frames++;blockSize=next;}
            }
        }
        if(crc!=0) throw new IOException("FLAC音频帧校验失败，文件可能不完整");
        total+=blockSize;frames++;
        if(samples!=0 && total!=samples) throw new IOException("FLAC采样数不完整："+total+" / "+samples);
    }
    static final int[] FLAC_CRC=new int[256];
    static {for(int i=0;i<256;i++){int c=i<<8;for(int j=0;j<8;j++)c=((c<<1)^((c&32768)!=0?0x8005:0))&65535;FLAC_CRC[i]=c;}}
    static int flacBlockSize(byte[] a,int p) {
        try {
            if(p+6>=a.length || (a[p]&255)!=255 || (a[p+1]&254)!=248)return -1;
            int code=(a[p+2]>>>4)&15,sr=a[p+2]&15,channels=(a[p+3]>>>4)&15,bits=(a[p+3]>>>1)&7;
            if(code==0 || sr==15 || channels>10 || bits==3 || (a[p+3]&1)!=0)return -1;
            int q=p+4,first=a[q++]&255,count=0;
            if(first>=128){int mask=128;while((first&mask)!=0){count++;mask>>>=1;}if(count<2 || count>7)return -1;for(int k=1;k<count;k++)if((a[q++]&192)!=128)return -1;}
            int block;
            if(code==1)block=192;
            else if(code<=5)block=576<<(code-2);
            else if(code==6)block=(a[q++]&255)+1;
            else if(code==7){block=((a[q]&255)<<8|(a[q+1]&255))+1;q+=2;}
            else block=256<<(code-8);
            if(sr==12)q++;else if(sr==13 || sr==14)q+=2;
            int crc=0;
            for(int k=p;k<=q;k++){crc^=a[k]&255;for(int j=0;j<8;j++)crc=((crc<<1)^((crc&128)!=0?7:0))&255;}
            return crc==0?block:-1;
        }catch(IndexOutOfBoundsException e){return -1;}
    }
    static void validateMp3(byte[] a) throws IOException {
        int p=0,frames=0,end=mp3AudioEnd(a);
        while(p+10<=end && matches(a,p,"ID3")) {
            // The tag size excludes its header and optional footer.
            int nsize=0;for(int i=6;i<10;i++){if((a[p+i]&128)!=0)throw new IOException("ID3长度异常");nsize=(nsize<<7)|(a[p+i]&127);}
            long next=(long)p+10+nsize+((a[p+3]==4 && (a[p+5]&16)!=0)?10:0);
            if(next>end)throw new IOException("ID3标签不完整");
            p=(int)next;
        }
        while(p+4<=end) {
            int h=(a[p]&255)<<24|(a[p+1]&255)<<16|(a[p+2]&255)<<8|(a[p+3]&255);
            int n=mp3FrameLength(h);
            if(n<0)throw new IOException("MP3音频帧异常，位置："+p);
            if(p+n>end) throw new IOException("MP3音频帧不完整");
            p+=n;frames++;
        }
        if(frames==0 || p!=end) throw new IOException("MP3音频完整性检查未通过");
    }
    static final int[][] MP3_RATES={{0,32,40,48,56,64,80,96,112,128,160,192,224,256,320},
                                   {0,8,16,24,32,40,48,56,64,80,96,112,128,144,160}};
    static int mp3FrameLength(int h) {
        int v=(h>>>19)&3,layer=(h>>>17)&3,r=(h>>>12)&15,s=(h>>>10)&3;
        if((h>>>21)!=2047 || v==1 || layer!=1 || r==0 || r==15 || s==3)return -1;
        int hz=new int[]{44100,48000,32000}[s]/(v==3?1:v==2?2:4);
        return (v==3?144:72)*MP3_RATES[v==3?0:1][r]*1000/hz+((h>>>9)&1);
    }
    static boolean matches(byte[] a,int p,String marker) {
        if(p<0 || p+marker.length()>a.length)return false;
        for(int i=0;i<marker.length();i++)if((a[p+i]&255)!=marker.charAt(i))return false;
        return true;
    }
    static long unsignedLE(byte[] a,int p) {return ByteBuffer.wrap(a,p,4).order(ByteOrder.LITTLE_ENDIAN).getInt()&0xffffffffL;}
    static int mp3AudioEnd(byte[] a) throws IOException {
        int end=a.length;
        for(int count=0;count<8;count++) {
            if(end>=128 && matches(a,end-128,"TAG")){end-=128;continue;}
            if(end>=32 && matches(a,end-32,"APETAGEX")) {
                int footer=end-32;long version=unsignedLE(a,footer+8),size=unsignedLE(a,footer+12),items=unsignedLE(a,footer+16),flags=unsignedLE(a,footer+20);
                if((version!=1000 && version!=2000) || size<32 || size>end || (flags&0x20000000L)!=0 || items>(size-32)/10)
                    throw new IOException("APE标签长度异常");
                int start=(int)(end-size),q=start;
                for(long item=0;item<items;item++) {
                    if(q+8>footer)throw new IOException("APE标签项目不完整");
                    long length=unsignedLE(a,q);q+=8;
                    int key=q;while(q<footer && a[q]!=0)q++;
                    if(q==key || q>=footer || length>footer-q-1)throw new IOException("APE标签项目长度异常");
                    q+=(int)length+1;
                }
                if(q!=footer)throw new IOException("APE标签长度不匹配");
                if((flags&0x80000000L)!=0) {
                    if(start<32 || !matches(a,start-32,"APETAGEX") || unsignedLE(a,start-20)!=size)
                        throw new IOException("APE标签头不完整");
                    start-=32;
                }
                end=start;continue;
            }
            if(end>=20 && matches(a,end-10,"3DI")) {
                int footer=end-10,size=0;
                for(int i=6;i<10;i++){if((a[footer+i]&128)!=0)throw new IOException("ID3尾标签长度异常");size=(size<<7)|(a[footer+i]&127);}
                int start=end-20-size;
                if(start<0 || !matches(a,start,"ID3") || a[start+3]!=4 || (a[start+5]&16)==0)
                    throw new IOException("ID3尾标签不完整");
                for(int i=3;i<10;i++)if(a[start+i]!=a[footer+i])throw new IOException("ID3尾标签不匹配");
                end=start;continue;
            }
            break;
        }
        return end;
    }
    public static void main(String[] args) throws Exception {
        if(args.length==0) {
            SwingUtilities.invokeLater(()->new NcmWindow().show());
            return;
        }
        boolean gui=args.length==0;
        List<Path> inputs=new ArrayList<>();
        Path outputOverride=null;
        if(gui) {
            UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName());
            JFileChooser chooser=new JFileChooser(new File(System.getProperty("user.home"),"Music"));
            chooser.setDialogTitle("选择NCM文件或文件夹（可多选）");
            chooser.setFileSelectionMode(JFileChooser.FILES_AND_DIRECTORIES);
            chooser.setMultiSelectionEnabled(true);
            if(chooser.showOpenDialog(null)!=JFileChooser.APPROVE_OPTION) return;
            for(File f:chooser.getSelectedFiles()) inputs.add(f.toPath());
        } else for(int i=0;i<args.length;i++) {
            if(args[i].equals("--output")) {
                if(++i>=args.length) throw new IllegalArgumentException("--output需要指定文件夹");
                outputOverride=Paths.get(args[i]);
            } else inputs.add(Paths.get(args[i]));
        }
        Set<Path> files=new LinkedHashSet<>(); List<String> failures=new ArrayList<>();
        for(Path input:inputs) {
            try {
                if(Files.isDirectory(input)) {
                    try(java.util.stream.Stream<Path> walk=Files.walk(input)) {
                        walk.filter(Files::isRegularFile).filter(NcmConvert::isNcm)
                            .forEach(p->files.add(p.toAbsolutePath().normalize()));
                    }
                } else if(Files.isRegularFile(input) && isNcm(input)) files.add(input.toAbsolutePath().normalize());
                else failures.add(input+"：文件不存在或不是.ncm文件");
            } catch(Exception e) { failures.add(input+"："+e.getMessage()); }
        }
        int success=0;
        for(Path f:files) {
            try { Path result=outputOverride==null?convert(f):convert(f,outputOverride); success++; System.out.println("成功："+result); }
            catch(Exception e) { String message=f.getFileName()+"："+e.getClass().getSimpleName()+" "+e.getMessage(); failures.add(message); System.err.println("失败："+message); }
        }
        String summary="转换结束：成功 "+success+" 个，失败 "+failures.size()+" 个。\n"+
            (outputOverride==null?"输出在各原文件旁的“转换结果”文件夹。":"保存到："+outputOverride)+
            "\n原文件保留；相同音频复用已有结果，不同内容自动编号。";
        if(files.isEmpty() && failures.isEmpty()) summary="没有找到.ncm文件。";
        System.out.println(summary);
        if(gui) {
            JTextArea text=new JTextArea(summary+(failures.isEmpty()?"":"\n\n"+String.join("\n",failures)),14,65);
            text.setFont(new java.awt.Font("Monospaced",java.awt.Font.PLAIN,14));
            text.setEditable(false); text.setLineWrap(true); text.setWrapStyleWord(true);
            JOptionPane.showMessageDialog(null,new JScrollPane(text),"NCM转换工具",failures.isEmpty()?JOptionPane.INFORMATION_MESSAGE:JOptionPane.WARNING_MESSAGE);
        }
        if(!failures.isEmpty()) System.exit(1);
    }
    static boolean isNcm(Path p) {return p.getFileName().toString().toLowerCase(Locale.ROOT).endsWith(".ncm");}
}
