using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Linq;
using System.Threading.Tasks;
using System.Management;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Oco.ClashMonitor {
    public sealed class Rate {
        public double Down, Up;
        public bool Valid;
        public Rate(double down,double up,bool valid) { Down=down; Up=up; Valid=valid; }
        public static Rate Between(long oldRx,long oldTx,long rx,long tx,double seconds) {
            if(double.IsNaN(seconds) || double.IsInfinity(seconds) || seconds<=0 || seconds>30 || oldRx<0 || oldTx<0 || rx<oldRx || tx<oldTx)
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
        public double Cpu=-1, Memory=-1, CoreCpu=-1, DiskBusy=-1, GpuEngine=-1, Battery=-1;
        public long DiskRead=-1, DiskWrite=-1, NetworkTick;
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
        readonly bool hardware;
        long hardwareTick;
        double diskBusy=-1,gpu=-1;
        long diskRead=-1,diskWrite=-1;
        static double Number(object value) { try { return value==null?-1:Convert.ToDouble(value); } catch {return -1;} }
        void Hardware(SystemSample s, long now) {
            if(!hardware)return;
            if(hardwareTick==0 || (now-hardwareTick)/(double)Stopwatch.Frequency>=15) {
                diskBusy=gpu=-1; diskRead=diskWrite=-1;
                var options=new EnumerationOptions { Timeout=TimeSpan.FromSeconds(3), ReturnImmediately=true };
                try {
                    using(var q=new ManagementObjectSearcher("root\\cimv2","SELECT PercentIdleTime,DiskReadBytesPersec,DiskWriteBytesPersec FROM Win32_PerfFormattedData_PerfDisk_PhysicalDisk WHERE Name='_Total'",options))
                    using(var rows=q.Get()) foreach(ManagementObject row in rows) using(row) {
                        var idle=Number(row["PercentIdleTime"]);
                        if(idle>=0 && idle<=100)diskBusy=100-idle;
                        diskRead=(long)Number(row["DiskReadBytesPersec"]);diskWrite=(long)Number(row["DiskWriteBytesPersec"]);
                    }
                } catch {}
                try {
                    var engines=new Dictionary<string,double>(StringComparer.OrdinalIgnoreCase);
                    using(var q=new ManagementObjectSearcher("root\\cimv2","SELECT Name,UtilizationPercentage FROM Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine",options))
                    using(var rows=q.Get()) foreach(ManagementObject row in rows) using(row) {
                        string name=Convert.ToString(row["Name"]);int idx=name.IndexOf("_luid_",StringComparison.OrdinalIgnoreCase);
                        double v=Number(row["UtilizationPercentage"]);
                        if(idx<0 || v<0)continue;
                        string id=name.Substring(idx); double sum;engines.TryGetValue(id,out sum);engines[id]=sum+v;
                    }
                    if(engines.Count>0)gpu=Math.Min(100,engines.Values.Max());
                } catch {}
                hardwareTick=Stopwatch.GetTimestamp();
            }
            s.DiskBusy=diskBusy;s.DiskRead=diskRead;s.DiskWrite=diskWrite;s.GpuEngine=gpu;
            try {var power=SystemInformation.PowerStatus;if((power.BatteryChargeStatus&BatteryChargeStatus.NoSystemBattery)==0 && power.BatteryChargeStatus!=BatteryChargeStatus.Unknown && power.BatteryLifePercent>=0 && power.BatteryLifePercent<=1)s.Battery=100*power.BatteryLifePercent;}catch{}
        }
        public Sampler(string[] ids) : this(ids,true) {}
        public Sampler(string[] ids,bool hardwareEnabled) { physical=new HashSet<string>((ids??new string[0]).Select(Normalize),StringComparer.OrdinalIgnoreCase);hardware=hardwareEnabled; }
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
            s.NetworkTick=Stopwatch.GetTimestamp();Hardware(s,now);
            return s;
        }
    }
    public sealed class MonitorForm:Form {
        readonly Sampler sampler;
        readonly Timer timer=new Timer();
        readonly Label status=new Label(),cpu=new Label(),ram=new Label(),core=new Label(),hardwareLabel=new Label();
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
            l.Text=text;l.Left=left;l.Top=63;l.Width=285;l.Height=65;l.Font=new Font("Segoe UI",13,FontStyle.Bold);l.ForeColor=TextFg;l.BackColor=PanelBg;l.TextAlign=ContentAlignment.MiddleCenter;Controls.Add(l);return l;
        }
        public MonitorForm(string[] physical,int interval,bool smoke,bool hardwareEnabled) {
            sampler=new Sampler(physical,hardwareEnabled);
            Text="Clash Verge Rev | Network & PC Monitor (Preview)";Font=new Font("Segoe UI",10);BackColor=Bg;ForeColor=TextFg;ClientSize=new Size(940,500);MinimumSize=new Size(960,540);StartPosition=FormStartPosition.CenterScreen;
            var heading=new Label{Text="NETWORK & PC MONITOR",Left=18,Top=12,Width=420,Height=36,ForeColor=Color.FromArgb(99,218,174),Font=new Font("Segoe UI",17,FontStyle.Bold)};Controls.Add(heading);
            var pin=new CheckBox{Text="Always on top",Left=625,Top=20,Width=150,ForeColor=TextFg};pin.CheckedChanged+=(a,b)=>TopMost=pin.Checked;pin.Anchor=AnchorStyles.Top|AnchorStyles.Right;Controls.Add(pin);
            Metric(cpu,"CPU  N/A",18);Metric(ram,"RAM  N/A",327);Metric(core,"Mihomo  N/A",636);
            hardwareLabel.SetBounds(18,137,900,45);hardwareLabel.ForeColor=TextFg;hardwareLabel.BackColor=PanelBg;hardwareLabel.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right;hardwareLabel.TextAlign=ContentAlignment.MiddleLeft;hardwareLabel.Text=hardwareEnabled?"Hardware sampling ...":"Optional hardware counters disabled";Controls.Add(hardwareLabel);
            grid.Left=18;grid.Top=195;grid.Width=904;grid.Height=240;grid.Anchor=AnchorStyles.Top|AnchorStyles.Bottom|AnchorStyles.Left|AnchorStyles.Right;grid.BackgroundColor=PanelBg;grid.BorderStyle=BorderStyle.None;grid.ReadOnly=true;grid.AllowUserToAddRows=false;grid.AllowUserToDeleteRows=false;grid.RowHeadersVisible=false;grid.AutoSizeColumnsMode=DataGridViewAutoSizeColumnsMode.Fill;grid.SelectionMode=DataGridViewSelectionMode.FullRowSelect;grid.EnableHeadersVisualStyles=false;
            grid.DefaultCellStyle.BackColor=PanelBg;grid.DefaultCellStyle.ForeColor=TextFg;grid.DefaultCellStyle.SelectionBackColor=Color.FromArgb(50,75,100);grid.ColumnHeadersDefaultCellStyle.BackColor=Bg;grid.ColumnHeadersDefaultCellStyle.ForeColor=Muted;
            foreach(string col in new[]{"Adapter","Classification","State","Down","Up","Link","Session RX / TX"})grid.Columns.Add(col,col);
            grid.Columns[0].FillWeight=115;grid.Columns[1].FillWeight=115;grid.Columns[6].FillWeight=150;Controls.Add(grid);
            status.Left=18;status.Top=445;status.Width=904;status.Height=45;status.Anchor=AnchorStyles.Bottom|AnchorStyles.Left|AnchorStyles.Right;status.ForeColor=Muted;Controls.Add(status);
            timer.Interval=interval;timer.Tick+=(a,b)=>RefreshSample();Shown+=(a,b)=>{RefreshSample();timer.Start();};
            FormClosed+=(a,b)=>{timer.Stop();timer.Dispose();};
            if(smoke){var stop=new Timer{Interval=20000};stop.Tick+=(a,b)=>{stop.Stop();stop.Dispose();Close();};Shown+=(a,b)=>stop.Start();}
        }
        async void RefreshSample(){
            if(busy || IsDisposed || Disposing)return;busy=true;
            try{
                var s=await Task.Run(()=>sampler.Take());
                if(IsDisposed || Disposing)return;
                long now=s.NetworkTick;double seconds=(now-prevTick)/(double)Stopwatch.Frequency;
                hardwareLabel.Text="Disk non-idle: "+Percent(s.DiskBusy)+"  |  GPU busiest engine: "+Percent(s.GpuEngine)+"  |  Battery: "+Percent(s.Battery)
                    +"\nDisk read: "+(s.DiskRead<0?"N/A":RateText(s.DiskRead))+"  |  write: "+(s.DiskWrite<0?"N/A":RateText(s.DiskWrite));

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
            }catch(Exception ex){if(!IsDisposed&&!Disposing){status.Text="Sample unavailable: "+ex.GetType().Name;cpu.Text=ram.Text=core.Text=hardwareLabel.Text="N/A";grid.Rows.Clear();prior.Clear();prevTick=0;}}finally{busy=false;}
        }
    }
    public static class Entry {
        public static void Run(string[] physical,int interval,bool smoke,bool hardwareEnabled) {
            Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            using(var f=new MonitorForm(physical,interval,smoke,hardwareEnabled)){Application.Run(f);if(smoke&&f.Samples<2)throw new Exception("GUI smoke insufficient samples");}
        }
        public static string SelfTest() {
            var a=Rate.Between(100,200,1100,700,2);
            if(!a.Valid||a.Down!=500||a.Up!=250)throw new Exception("normal delta");
            if(Rate.Between(100,200,99,700,2).Valid)throw new Exception("reset");
            if(Rate.Between(100,200,1100,700,0).Valid)throw new Exception("zero interval");
            if(Rate.Between(100,200,1100,700,31).Valid)throw new Exception("stale interval");
            if(!Rate.Between(100,200,100,200,2).Valid)throw new Exception("idle");
            if(Rate.Between(100,200,1100,700,double.NaN).Valid)throw new Exception("invalid interval");
            if(Rate.Between(100,200,1100,199,2).Valid)throw new Exception("tx reset");
            return "MONITOR_SELF_TEST_OK 7 rate assertions";
        }
    }
}
