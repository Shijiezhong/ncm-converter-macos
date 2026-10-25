import java.awt.*;
import java.awt.datatransfer.*;
import java.awt.event.*;
import java.io.*;
import java.nio.file.*;
import java.nio.BufferUnderflowException;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.List;
import javax.swing.*;
import javax.swing.table.*;
import javax.swing.plaf.FontUIResource;

/** Local GUI. Conversion runs off the event thread; no network access. */
public class NcmWindow {
    final JFrame frame=new JFrame("NCM转换工具 · 2.0");
    final DefaultTableModel model=new DefaultTableModel(new String[]{"文件","状态","结果 / 原因"},0) {
        public boolean isCellEditable(int row,int col){return false;}
    };
    final JTable table=new JTable(model);
    final List<Path> sources=new ArrayList<>();
    final Set<Path> seen=new HashSet<>();
    final JButton add=new JButton("添加文件或文件夹"),clear=new JButton("清空列表"),
        choose=new JButton("更改保存位置"),start=new JButton("开始转换"),open=new JButton("打开结果文件夹"),
        cancel=new JButton("停止后续转换");
    final JLabel destination=new JLabel(),status=new JLabel("添加文件后点击“开始转换”。也可以直接拖入文件或文件夹。");
    final JProgressBar progress=new JProgressBar();
    Path output=Paths.get(System.getProperty("user.home"),"Desktop","NCM转换结果");
    volatile boolean stop=false;
    boolean busy=false;

    public NcmWindow() {
        FontUIResource font=new FontUIResource("PingFang SC",Font.PLAIN,15);
        Enumeration<Object> keys=UIManager.getDefaults().keys();
        while(keys.hasMoreElements()){Object key=keys.nextElement();if(UIManager.get(key) instanceof Font) UIManager.put(key,font);}
        SwingUtilities.updateComponentTreeUI(frame);
        frame.setDefaultCloseOperation(JFrame.DO_NOTHING_ON_CLOSE);
        frame.addWindowListener(new WindowAdapter(){public void windowClosing(WindowEvent e){
            if(busy){status.setText("正在处理当前文件，请先停止后续转换并等待完成。");return;}
            frame.dispose();
        }});
        JPanel root=new JPanel(new BorderLayout(12,12));root.setBorder(BorderFactory.createEmptyBorder(20,22,20,22));
        JPanel top=new JPanel();top.setLayout(new BoxLayout(top,BoxLayout.Y_AXIS));
        JLabel title=new JLabel("把 NCM 音乐放进来，批量转换");title.setFont(new Font("PingFang SC",Font.BOLD,22));
        top.add(title);top.add(Box.createVerticalStrut(7));
        top.add(new JLabel("保留原文件 · 自动处理已知封面异常 · 输出原音频 MP3 或 FLAC"));
        JPanel controls=new JPanel(new FlowLayout(FlowLayout.LEFT,8,10));controls.add(add);controls.add(clear);top.add(controls);
        root.add(top,BorderLayout.NORTH);
        table.setFont(new Font("PingFang SC",Font.PLAIN,14));table.setRowHeight(32);
        table.getTableHeader().setFont(new Font("PingFang SC",Font.BOLD,14));
        table.setAutoResizeMode(JTable.AUTO_RESIZE_LAST_COLUMN);
        table.getColumnModel().getColumn(0).setPreferredWidth(290);
        table.getColumnModel().getColumn(1).setPreferredWidth(85);
        table.getColumnModel().getColumn(2).setPreferredWidth(430);
        table.setFillsViewportHeight(true);
        JScrollPane scroll=new JScrollPane(table);
        root.add(scroll,BorderLayout.CENTER);
        TransferHandler drops=new TransferHandler(){
            public boolean canImport(TransferSupport s){return !busy && s.isDataFlavorSupported(DataFlavor.javaFileListFlavor);}
            public boolean importData(TransferSupport s){
                if(!canImport(s))return false;
                try {@SuppressWarnings("unchecked") List<File> files=(List<File>)s.getTransferable().getTransferData(DataFlavor.javaFileListFlavor);addFiles(files);return true;}
                catch(Exception e){status.setText("无法读取拖入的文件，请使用“添加文件或文件夹”。");return false;}
            }
        };
        root.setTransferHandler(drops);table.setTransferHandler(drops);scroll.setTransferHandler(drops);
        JPanel bottom=new JPanel();bottom.setLayout(new BoxLayout(bottom,BoxLayout.Y_AXIS));
        JPanel out=new JPanel(new BorderLayout(8,0));out.add(destination,BorderLayout.CENTER);out.add(choose,BorderLayout.EAST);
        bottom.add(out);bottom.add(Box.createVerticalStrut(10));progress.setStringPainted(true);progress.setString("等待添加文件");bottom.add(progress);
        bottom.add(Box.createVerticalStrut(8));bottom.add(status);
        JPanel actions=new JPanel(new FlowLayout(FlowLayout.RIGHT));actions.add(open);actions.add(cancel);actions.add(start);bottom.add(actions);
        root.add(bottom,BorderLayout.SOUTH);frame.setContentPane(root);
        frame.setMinimumSize(new Dimension(850,480));frame.setSize(1000,610);frame.setLocationRelativeTo(null);
        add.addActionListener(e->{JFileChooser f=picker();f.setMultiSelectionEnabled(true);f.setFileSelectionMode(JFileChooser.FILES_AND_DIRECTORIES);if(f.showOpenDialog(frame)==JFileChooser.APPROVE_OPTION)addFiles(Arrays.asList(f.getSelectedFiles()));});
        clear.addActionListener(e->{sources.clear();seen.clear();model.setRowCount(0);refresh();status.setText("列表已清空，原文件和转换结果均保留。");});
        choose.addActionListener(e->{JFileChooser f=picker();f.setFileSelectionMode(JFileChooser.DIRECTORIES_ONLY);if(f.showOpenDialog(frame)==JFileChooser.APPROVE_OPTION){output=f.getSelectedFile().toPath();refresh();}});
        start.addActionListener(e->run());
        open.addActionListener(e->{try{Files.createDirectories(output);Desktop.getDesktop().open(output.toFile());}catch(Exception x){JOptionPane.showMessageDialog(frame,"无法打开文件夹："+output+"\n"+x.getMessage());}});
        cancel.addActionListener(e->{stop=true;cancel.setEnabled(false);status.setText("当前文件完成后停止；已生成的结果保留。");});
        SwingUtilities.updateComponentTreeUI(frame);refresh();
    }
    JFileChooser picker(){JFileChooser f=new JFileChooser(new File(System.getProperty("user.home"),"Desktop"));f.setDialogTitle("选择 NCM 文件或文件夹");return f;}
    void refresh(){destination.setText("保存到："+output);destination.setToolTipText(output.toString());start.setEnabled(!busy&&!sources.isEmpty());add.setEnabled(!busy);clear.setEnabled(!busy);choose.setEnabled(!busy);cancel.setEnabled(busy);}
    void addFiles(List<File> files){
        busy=true;refresh();status.setText("正在查找 NCM 文件…");
        new SwingWorker<List<Path>,Void>() {
            final List<String> errors=new ArrayList<>();
            protected List<Path> doInBackground(){
                List<Path> result=new ArrayList<>();
                for(File f:files)try{
                    Path p=f.toPath();
                    if(Files.isDirectory(p)){try(java.util.stream.Stream<Path> walk=Files.walk(p)){walk.filter(Files::isRegularFile).filter(NcmConvert::isNcm).forEach(result::add);}}
                    else if(NcmConvert.isNcm(p))result.add(p);
                }catch(Exception e){errors.add(f.getName()+"："+e.getMessage());}
                return result;
            }
            protected void done(){
                int count=0;
                try{for(Path p:get()){Path normalized=p.toRealPath();if(seen.add(normalized)){sources.add(normalized);model.addRow(new Object[]{normalized.getFileName(),"待转换",""});count++;}}}
                catch(Exception e){errors.add("部分文件无法读取："+e.getMessage());}
                busy=false;refresh();progress.setString("共 "+sources.size()+" 个文件");
                status.setText("新增 "+count+" 个 NCM 文件；重复选择的文件自动忽略。"+(errors.isEmpty()?"":" 部分路径无法访问。"));
                if(!errors.isEmpty()) JOptionPane.showMessageDialog(frame,String.join("\n",errors),"读取提示",JOptionPane.WARNING_MESSAGE);
            }
        }.execute();
    }
    void run(){
        busy=true;stop=false;refresh();final Path dir=output;final List<Path> batch=new ArrayList<>(sources);
        progress.setMaximum(batch.size());progress.setValue(0);progress.setString("准备转换…");
        new SwingWorker<Void,Object[]>() {
            int ok=0,failed=0;final StringBuilder log=new StringBuilder("NCM转换工具 2.0\n时间："+new Date()+"\n输出："+dir+"\n\n");
            protected Void doInBackground(){
                for(int i=0;i<batch.size()&&!stop;i++) {
                    Path file=batch.get(i);publish(new Object[]{i,"转换中","正在检查和导出…",i});
                    try{Path target=NcmConvert.convert(file,dir);ok++;publish(new Object[]{i,"成功",target.toString(),i+1});log.append("成功：").append(file).append(" → ").append(target).append('\n');}
                    catch(Exception e){failed++;String reason=friendly(e);publish(new Object[]{i,"失败",reason,i+1});log.append("失败：").append(file).append("\n原因：").append(e.toString()).append('\n');}
                }
                try{Files.createDirectories(dir);Path report=Files.createTempFile(dir,"转换记录-",".txt");Files.write(report,log.toString().getBytes(StandardCharsets.UTF_8));}
                catch(Exception e){log.append("记录保存失败：").append(e.getMessage());}
                return null;
            }
            protected void process(List<Object[]> changes){for(Object[] c:changes){int row=(Integer)c[0];model.setValueAt(c[1],row,1);model.setValueAt(c[2],row,2);progress.setValue((Integer)c[3]);progress.setString((Integer)c[3]+" / "+batch.size());status.setText(c[1]+"："+batch.get(row).getFileName());}}
            protected void done(){
                busy=false;refresh();
                try{get();status.setText((stop?"已停止":"转换完成")+"：成功 "+ok+" 个，失败 "+failed+" 个。点击“打开结果文件夹”查看。");}
                catch(Exception e){status.setText("任务未完成："+e.getMessage()+"；已成功的结果保留。");}
                progress.setString("成功 "+ok+"  /  失败 "+failed+(stop?"  /  已停止":""));
            }
        }.execute();
    }
    static String friendly(Exception e){
        if(e instanceof AccessDeniedException)return "没有文件访问权限，请换到桌面文件夹后重试。";
        if(e instanceof NoSuchFileException)return "文件已移动或尚未下载，请确认文件在本机可用。";
        if(e instanceof javax.crypto.BadPaddingException)return "NCM密钥无法读取，可能是格式不支持或文件不完整。";
        if(e instanceof BufferUnderflowException)return "文件不完整，请重新下载后再试。";
        return e.getMessage()==null?e.getClass().getSimpleName():e.getMessage();
    }
    public void show(){frame.setVisible(true);}
}
