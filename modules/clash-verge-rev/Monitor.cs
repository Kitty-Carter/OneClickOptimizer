using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Oco.ClashMonitor {
    public sealed class Rate {
        public double Down, Up;
        public bool Valid;
        public Rate(double down,double up,bool valid) { Down=down; Up=up; Valid=valid; }
        public static Rate Between(long oldRx,long oldTx,long rx,long tx,double seconds) {
            if(seconds<=0 || seconds>30 || oldRx<0 || oldTx<0 || rx<oldRx || tx<oldTx)
                return new Rate(0,0,false);
            return new Rate((rx-oldRx)/seconds,(tx-oldTx)/seconds,true);
        }
    }
    public sealed class AdapterSample {
        public string Id, Name, Kind, State;
        public long Rx, Tx, Link;
        public bool Available;
    }
    public sealed class SystemSample {
        public double Cpu=-1, Memory=-1, CoreCpu=-1;
        public long TotalMemory, AvailableMemory, CoreWorkingSet, CorePrivate;
        public int CoreCount;
        public List<AdapterSample> Adapters=new List<AdapterSample>();
    }
    public sealed class Sampler {
        [StructLayout(LayoutKind.Sequential)]
        struct MemoryStatus {
            public uint Length, Load;
            public ulong Total, Available, PageTotal, PageAvailable, VirtualTotal, VirtualAvailable, Extended;
        }
        [StructLayout(LayoutKind.Sequential)] struct FileTime {public uint Low, High; public ulong Value {get{return ((ulong)High<<32)|Low;}}}
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GlobalMemoryStatusEx(ref MemoryStatus x);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetSystemTimes(out FileTime idle,out FileTime kernel,out FileTime user);
        ulong lastIdle,lastKernel,lastUser; bool haveCpu;
        readonly Dictionary<int,double> prevCore=new Dictionary<int,double>();
        long lastCoreTick;
        readonly HashSet<string> physical;
        public Sampler(string[] ids) { physical=new HashSet<string>((ids??new string[0]).Select(Normalize),StringComparer.OrdinalIgnoreCase); }
        static string Normalize(string id){return (id??"").Trim().Trim('{','}');}
        public SystemSample Take() {
            var s=new SystemSample();
            FileTime i,k,u;
            if(GetSystemTimes(out i,out k,out u)){
                if(haveCpu && i.Value>=lastIdle && k.Value>=lastKernel && u.Value>=lastUser){
                    double total=(double)(k.Value-lastKernel)+(u.Value-lastUser);
                    if(total>0) s.Cpu=Math.Max(0,Math.Min(100,100*(1-(i.Value-lastIdle)/total)));
                }
                lastIdle=i.Value;lastKernel=k.Value;lastUser=u.Value;haveCpu=true;
            }
            var m=new MemoryStatus();m.Length=(uint)Marshal.SizeOf(typeof(MemoryStatus));
            if(GlobalMemoryStatusEx(ref m)){s.TotalMemory=(long)m.Total;s.AvailableMemory=(long)m.Available;s.Memory=m.Load;}
            var current=new Dictionary<int,double>();var now=Stopwatch.GetTimestamp();
            double coreDelta=0;bool coreValid=false;
            foreach(var p in Process.GetProcessesByName("verge-mihomo")) using(p) {
                try {
                    s.CoreCount++;s.CoreWorkingSet+=p.WorkingSet64;s.CorePrivate+=p.PrivateMemorySize64;
                    double cpu=p.TotalProcessorTime.TotalSeconds;current[p.Id]=cpu;
                    double old;if(prevCore.TryGetValue(p.Id,out old)&&cpu>=old){coreDelta+=cpu-old;coreValid=true;}
                } catch {}
            }
            double elapsed=(now-lastCoreTick)/(double)Stopwatch.Frequency;
            if(lastCoreTick!=0&&elapsed>0&&elapsed<=30&&coreValid)
                s.CoreCpu=Math.Max(0,Math.Min(100,100*coreDelta/elapsed/Environment.ProcessorCount));
            lastCoreTick=now;prevCore.Clear();foreach(var p in current)prevCore[p.Key]=p.Value;
            foreach(var n in NetworkInterface.GetAllNetworkInterfaces()){
                if(n.NetworkInterfaceType==NetworkInterfaceType.Loopback)continue;
                var a=new AdapterSample{Id=n.Id,Name=n.Name,State=n.OperationalStatus.ToString(),Kind="Other / unclassified"};
                if(physical.Contains(Normalize(n.Id))) a.Kind="Physical";
                else if(n.NetworkInterfaceType==NetworkInterfaceType.Tunnel || n.Name.Equals("Mihomo",StringComparison.OrdinalIgnoreCase)||n.Name.Equals("Meta",StringComparison.OrdinalIgnoreCase))a.Kind="Tunnel candidate";
                try {a.Link=n.Speed; var v=n.GetIPStatistics();a.Rx=v.BytesReceived;a.Tx=v.BytesSent;a.Available=n.OperationalStatus==OperationalStatus.Up&&a.Rx>=0&&a.Tx>=0;}catch{}
                s.Adapters.Add(a);
            }
            return s;
        }
    }
    public sealed class MonitorForm:Form {
        readonly Sampler sampler;
        readonly Timer timer=new Timer();
        readonly Label status=new Label(),cpu=new Label(),ram=new Label(),core=new Label();
        readonly DataGridView grid=new DataGridView();
        readonly Dictionary<string,AdapterSample> prior=new Dictionary<string,AdapterSample>(StringComparer.OrdinalIgnoreCase);
        readonly Dictionary<string,double[]> totals=new Dictionary<string,double[]>(StringComparer.OrdinalIgnoreCase);
        long prevTick; bool busy;
        public int Samples {get;private set;}
        static Color Bg=Color.FromArgb(18,24,33),PanelBg=Color.FromArgb(31,42,56),TextFg=Color.FromArgb(235,241,248),Muted=Color.FromArgb(160,179,200);
        static string RateText(double n){return n>=1000000?(n/1000000).ToString("F2")+" MB/s":(n/1000).ToString("F1")+" KB/s";}
        static string BytesText(double n){return n>=1073741824?(n/1073741824).ToString("F2")+" GiB":(n/1048576).ToString("F1")+" MiB";}
        static string Percent(double n){return n<0?"N/A":n.ToString("F1")+"%";}
        Label Metric(Label l,string text,int left) {
            l.Text=text;l.Left=left;l.Top=63;l.Width=245;l.Height=65;l.Font=new Font("Segoe UI",13,FontStyle.Bold);l.ForeColor=TextFg;l.BackColor=PanelBg;l.TextAlign=ContentAlignment.MiddleCenter;Controls.Add(l);return l;
        }
        public MonitorForm(string[] physical,int interval,bool smoke) {
            sampler=new Sampler(physical);
            Text="Clash Verge Rev | Network & PC Monitor (Preview)";Font=new Font("Segoe UI",10);BackColor=Bg;ForeColor=TextFg;ClientSize=new Size(800,420);MinimumSize=new Size(740,380);StartPosition=FormStartPosition.CenterScreen;
            var heading=new Label{Text="NETWORK & PC MONITOR",Left=18,Top=12,Width=420,Height=36,ForeColor=Color.FromArgb(99,218,174),Font=new Font("Segoe UI",17,FontStyle.Bold)};Controls.Add(heading);
            var pin=new CheckBox{Text="Always on top",Left=625,Top=20,Width=150,ForeColor=TextFg};pin.CheckedChanged+=(a,b)=>TopMost=pin.Checked;pin.Anchor=AnchorStyles.Top|AnchorStyles.Right;Controls.Add(pin);
            Metric(cpu,"CPU  —",18);Metric(ram,"RAM  —",278);Metric(core,"Mihomo  —",538);
            grid.Left=18;grid.Top=145;grid.Width=764;grid.Height=210;grid.Anchor=AnchorStyles.Top|AnchorStyles.Bottom|AnchorStyles.Left|AnchorStyles.Right;grid.BackgroundColor=PanelBg;grid.BorderStyle=BorderStyle.None;grid.ReadOnly=true;grid.AllowUserToAddRows=false;grid.AllowUserToDeleteRows=false;grid.RowHeadersVisible=false;grid.AutoSizeColumnsMode=DataGridViewAutoSizeColumnsMode.Fill;grid.SelectionMode=DataGridViewSelectionMode.FullRowSelect;grid.EnableHeadersVisualStyles=false;
            grid.DefaultCellStyle.BackColor=PanelBg;grid.DefaultCellStyle.ForeColor=TextFg;grid.DefaultCellStyle.SelectionBackColor=Color.FromArgb(50,75,100);grid.ColumnHeadersDefaultCellStyle.BackColor=Bg;grid.ColumnHeadersDefaultCellStyle.ForeColor=Muted;
            foreach(string col in new[]{"Adapter","Classification","State","Down","Up","Link","Session RX / TX"})grid.Columns.Add(col,col);
            grid.Columns[0].FillWeight=115;grid.Columns[1].FillWeight=115;grid.Columns[6].FillWeight=150;Controls.Add(grid);
            status.Left=18;status.Top=365;status.Width=764;status.Height=42;status.Anchor=AnchorStyles.Bottom|AnchorStyles.Left|AnchorStyles.Right;status.ForeColor=Muted;Controls.Add(status);
            timer.Interval=interval;timer.Tick+=(a,b)=>RefreshSample();Shown+=(a,b)=>{RefreshSample();timer.Start();};
            FormClosed+=(a,b)=>{timer.Stop();timer.Dispose();};
            if(smoke){var stop=new Timer{Interval=5500};stop.Tick+=(a,b)=>{stop.Stop();stop.Dispose();Close();};Shown+=(a,b)=>stop.Start();}
        }
        void RefreshSample(){
            if(busy)return;busy=true;
            try{
                var s=sampler.Take();long now=Stopwatch.GetTimestamp();double seconds=(now-prevTick)/(double)Stopwatch.Frequency;
                cpu.Text="CPU  "+Percent(s.Cpu);
                ram.Text="RAM  "+Percent(s.Memory)+(s.TotalMemory>0?"\n"+BytesText(s.TotalMemory-s.AvailableMemory)+" used":"");
                core.Text="Mihomo  "+s.CoreCount+" process(es)\n"+BytesText(s.CoreWorkingSet)+" WS | CPU "+Percent(s.CoreCpu);
                var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                grid.SuspendLayout();
                try{
                    grid.Rows.Clear();
                    foreach(var a in s.Adapters.OrderBy(x=>x.State=="Up"?0:1).ThenBy(x=>x.Name)){
                        seen.Add(a.Id);AdapterSample old;Rate rate=new Rate(0,0,false);
                        if(a.Available&&prior.TryGetValue(a.Id,out old)&&old.Available)rate=Rate.Between(old.Rx,old.Tx,a.Rx,a.Tx,seconds);
                        double[] sum;if(!totals.TryGetValue(a.Id,out sum)){sum=new double[2];totals[a.Id]=sum;}
                        if(rate.Valid){sum[0]+=rate.Down*seconds;sum[1]+=rate.Up*seconds;}
                        grid.Rows.Add(a.Name,a.Kind,a.State,rate.Valid?RateText(rate.Down):"—",rate.Valid?RateText(rate.Up):"—",a.Link>0?(a.Link/1000000.0).ToString("F0")+" Mbps":"—",BytesText(sum[0])+" / "+BytesText(sum[1]));
                        prior[a.Id]=a;
                    }
                    foreach(var id in prior.Keys.Where(x=>!seen.Contains(x)).ToArray())prior.Remove(id);
                    foreach(var id in totals.Keys.Where(x=>!seen.Contains(x)).ToArray())totals.Remove(id);
                } finally {grid.ResumeLayout();}
                prevTick=now;Samples++;
                status.Text="Separate NIC counters; never sum physical + tunnel. Session totals only. Core WS is not kernel heap. No external requests. "+DateTime.Now.ToString("HH:mm:ss");
            }catch(Exception ex){status.Text="Sample unavailable: "+ex.GetType().Name;grid.Rows.Clear();prior.Clear();prevTick=0;}finally{busy=false;}
        }
    }
    public static class Entry {
        public static void Run(string[] physical,int interval,bool smoke) {
            Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            using(var f=new MonitorForm(physical,interval,smoke)){Application.Run(f);if(smoke&&f.Samples<2)throw new Exception("GUI smoke insufficient samples");}
        }
        public static string SelfTest() {
            var a=Rate.Between(100,200,1100,700,2);
            if(!a.Valid||a.Down!=500||a.Up!=250)throw new Exception("normal delta");
            if(Rate.Between(100,200,99,700,2).Valid)throw new Exception("reset");
            if(Rate.Between(100,200,1100,700,0).Valid)throw new Exception("zero interval");
            if(Rate.Between(100,200,1100,700,31).Valid)throw new Exception("stale interval");
            if(!Rate.Between(100,200,100,200,2).Valid)throw new Exception("idle");
            return "MONITOR_SELF_TEST_OK 5 rate assertions";
        }
    }
}
