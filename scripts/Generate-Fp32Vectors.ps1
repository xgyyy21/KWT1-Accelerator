param([string]$OutputPath = 'build/fp32_vectors.txt', [int]$RandomPairs = 20000)
$ErrorActionPreference = 'Stop'
if (-not ('Fp32GoldenVectors' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public static class Fp32GoldenVectors {
    static float Float(uint bits) { return BitConverter.ToSingle(BitConverter.GetBytes(bits), 0); }
    static uint Bits(float value) {
        return Single.IsNaN(value) ? 0x7fc00000u : BitConverter.ToUInt32(BitConverter.GetBytes(value), 0);
    }
    static void Pair(StreamWriter writer, uint a, uint b) {
        float x = Float(a), y = Float(b);
        // Explicit float stores; these are separate operations, never FMA.
        float sum = x + y;
        float product = x * y;
        writer.WriteLine("{0:x8} {1:x8} {2:x8} {3:x8}", a, b, Bits(sum), Bits(product));
    }
    static uint Next(ref uint state) {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5; return state;
    }
    public static int Generate(string path, int randomPairs) {
        uint[] edge = {0u,0x80000000u,1u,0x80000001u,0x007fffffu,0x00800000u,
            0x00800001u,0x3f000000u,0x3f7fffffu,0x3f800000u,0x3f800001u,
            0xbf800000u,0x40000000u,0x7f7fffffu,0xff7fffffu,0x7f800000u,
            0xff800000u,0x7fc00001u,0x7f800001u,0x33800000u,0x33000001u};
        int count=0; uint state=0x12345678u;
        using(var writer=new StreamWriter(path, false, new UTF8Encoding(false))) {
            foreach(uint a in edge) foreach(uint b in edge) { Pair(writer,a,b); count++; }
            for(int i=0;i<randomPairs;i++) { uint a=Next(ref state),b=Next(ref state); Pair(writer,a,b); count++; }
        }
        return count;
    }
}
'@
}
$vectorDirectory = Split-Path -Parent $OutputPath
if ($vectorDirectory) { New-Item -ItemType Directory -Force -Path $vectorDirectory | Out-Null }
$vectorCount = [Fp32GoldenVectors]::Generate($OutputPath, $RandomPairs)
Write-Output "Generated $vectorCount FP32 add/mul pairs: $OutputPath"
