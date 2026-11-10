<#
.SYNOPSIS
  直连 SPL5 项目的 MySQL 查库，用于核对浏览器录入是否真的落库。

.DESCRIPTION
  本机通常没有 mysql client。SPL5 项目的 Spring Boot fat jar（target\*.jar）里自带
  BOOT-INF\lib\mysql-connector-java-*.jar，本脚本把它解出来，再用 JDK 11+ 的
  "单文件源码免编译" 能力跑一段内嵌的查询器，不需要额外安装任何东西。

  默认连接信息从 <项目>\src\main\resources\application.properties 读取
  （spring.datasource.url / username / password），所以对的是当前被测环境。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File dbq.ps1 -Sql "SELECT COUNT(*) FROM jsgczbxmbd"

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File dbq.ps1 -JarPath ..\swggzyjy2022\target\swggzyjy.jar `
      -Sql "SELECT id,bdmc FROM jsgczbxmbd WHERE id='xxx'" -MaxRows 20
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Sql,
    [string]$JarPath,
    [string]$DbUrl,
    [string]$DbUser,
    [string]$DbPass,
    [string]$ProjectRoot,
    [int]$MaxRows = 200
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }
$work = Join-Path $env:TEMP 'spl5-dbq'
New-Item -ItemType Directory -Force -Path $work | Out-Null

# ---------- 1. 连接信息：显式参数 > application.properties ----------
function Get-Prop([string]$file, [string]$key) {
    if (-not (Test-Path $file)) { return $null }
    $line = Get-Content -Path $file -Encoding UTF8 | Where-Object { $_ -like "$key=*" } | Select-Object -First 1
    if ($null -eq $line) { return $null }
    return ($line -split '=', 2)[1].Trim()
}

if (-not $ProjectRoot) { $ProjectRoot = (Get-Location).Path }
$props = Join-Path $ProjectRoot 'src\main\resources\application.properties'
if (-not (Test-Path $props)) {
    $found = Get-ChildItem -Path $ProjectRoot -Recurse -Filter 'application.properties' -File -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -notmatch '\\target\\' } | Select-Object -First 1
    if ($found) { $props = $found.FullName }
}

if (-not $DbUrl)  { $DbUrl  = Get-Prop $props 'spring.datasource.url' }
if (-not $DbUser) { $DbUser = Get-Prop $props 'spring.datasource.username' }
if (-not $DbPass) { $DbPass = Get-Prop $props 'spring.datasource.password' }

if (-not $DbUrl) { throw "找不到 spring.datasource.url。请用 -ProjectRoot 指向项目根目录，或直接传 -DbUrl/-DbUser/-DbPass。" }
if ($DbPass -match '^ENC\(') { throw "application.properties 里的密码是加密的，本脚本不解密；请显式传 -DbPass。" }
if (-not $DbUser) { $DbUser = 'root' }
if ($null -eq $DbPass) { $DbPass = '' }

Write-Host "连接: $DbUrl  用户: $DbUser" -ForegroundColor DarkGray

# ---------- 2. 找 mysql 驱动 ----------
if (-not $JarPath) {
    $jar = Get-ChildItem -Path $ProjectRoot -Recurse -Filter '*.jar' -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -notlike '*.original' -and $_.FullName -match '\\target\\' } |
           Sort-Object Length -Descending | Select-Object -First 1
    if ($jar) { $JarPath = $jar.FullName }
}
if (-not $JarPath -or -not (Test-Path $JarPath)) {
    throw "找不到 Spring Boot fat jar。请用 -JarPath 指向 <项目>\target\<app>.jar。"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($JarPath)
try {
    $entry = $zip.Entries | Where-Object { $_.FullName -match '^BOOT-INF/lib/mysql-connector.*\.jar$' } | Select-Object -First 1
    if (-not $entry) { throw "$JarPath 里没有 BOOT-INF/lib/mysql-connector*.jar" }
    $driver = Join-Path $work ([System.IO.Path]::GetFileName($entry.FullName))
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $driver, $true)
} finally { $zip.Dispose() }
Write-Host "驱动: $driver" -ForegroundColor DarkGray

# ---------- 3. JDK 11+（单文件源码免编译需要） ----------
$java = $null
foreach ($cand in @('D:\app\java\jdk-21\bin\java.exe', "$env:JAVA_HOME\bin\java.exe")) {
    if ($cand -and (Test-Path $cand)) { $java = $cand; break }
}
if (-not $java) {
    $cmd = Get-Command java -ErrorAction SilentlyContinue
    if ($cmd) { $java = $cmd.Source }
}
if (-not $java) { throw "找不到 java。需要 JDK 11 或更高（用于 java Q.java 免编译运行）。" }
Write-Host "Java: $java" -ForegroundColor DarkGray

# ---------- 4. 内嵌查询器 ----------
$javaSrc = @'
import java.sql.*;

public class Q {
    public static void main(String[] args) throws Exception {
        String url = System.getenv("DB_URL");
        String user = System.getenv("DB_USER");
        String pass = System.getenv("DB_PASS");
        int max = args.length > 1 ? Integer.parseInt(args[1]) : 200;
        Class.forName("com.mysql.cj.jdbc.Driver");
        try (Connection c = DriverManager.getConnection(url, user, pass);
             Statement st = c.createStatement();
             ResultSet rs = st.executeQuery(args[0])) {
            ResultSetMetaData md = rs.getMetaData();
            int n = md.getColumnCount();
            StringBuilder head = new StringBuilder();
            for (int i = 1; i <= n; i++) {
                if (i > 1) head.append(" | ");
                head.append(md.getColumnLabel(i));
            }
            System.out.println(head);
            int cnt = 0;
            while (rs.next() && cnt < max) {
                StringBuilder sb = new StringBuilder();
                for (int i = 1; i <= n; i++) {
                    if (i > 1) sb.append(" | ");
                    String v = rs.getString(i);
                    if (v != null && v.length() > 200) v = v.substring(0, 200) + "...";
                    // bit(1) columns read through CONCAT come back as binary; render control bytes as hex
                    if (v != null && !v.isEmpty() && v.chars().anyMatch(ch -> ch < 0x20 || ch == 0x7f)) {
                        StringBuilder hex = new StringBuilder();
                        for (byte b : v.getBytes("ISO-8859-1")) {
                            hex.append(String.format("%02X", b));
                        }
                        v = "0x" + hex;
                    }
                    sb.append(v);
                }
                System.out.println(sb);
                cnt++;
            }
            System.out.println("rows=" + cnt);
        }
    }
}
'@
$qfile = Join-Path $work 'Q.java'
# 源码保持纯 ASCII 且不带 BOM：javac 单文件模式按平台默认编码读源码，
# 中文注释在 GBK 机器上会编译失败；而 BOM 又会让 source launcher 报错
[System.IO.File]::WriteAllText($qfile, $javaSrc, (New-Object System.Text.UTF8Encoding($false)))

# ---------- 5. 执行 ----------
$env:DB_URL = $DbUrl
$env:DB_USER = $DbUser
$env:DB_PASS = $DbPass
$env:JAVA_TOOL_OPTIONS = '-Dstdout.encoding=UTF-8 -Dfile.encoding=UTF-8'
& $java -cp $driver $qfile $Sql $MaxRows
exit $LASTEXITCODE
