param(
  [Parameter(Mandatory=$true)][string]$Manifest,
  [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
$manifestPath=[IO.Path]::GetFullPath($Manifest)
$out=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $out){
  if((Get-ChildItem -LiteralPath $out -Force|Measure-Object).Count -ne 0){
    throw "Refusing to overwrite non-empty output directory: $out"
  }
}else{New-Item -ItemType Directory -Path $out|Out-Null}
$spec=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
if($spec.version -ne 1){throw 'Only manifest version 1 is supported'}
$m=[int]$spec.m;$k=[int]$spec.k;$n=[int]$spec.n;$shift=[int]$spec.out_shift
if($m -le 0 -or $n -le 0 -or ($k -ne 64 -and $k -ne 256) -or $shift -lt 0 -or $shift -gt 31){
  throw 'Unsupported M/K/N or out_shift'
}
$contract=@{input_dtype='int16';weight_dtype='int16';bias_dtype='int32';output_dtype='int16';
  layout='row_major';rounding='nearest_ties_away';overflow='saturate'}
foreach($key in $contract.Keys){if($spec.$key -cne $contract[$key]){throw "$key must be $($contract[$key])"}}
function Read-IntCsv([string]$Path,[int]$Rows,[int]$Cols,[long]$Min,[long]$Max){
  $result=[System.Collections.Generic.List[long]]::new()
  $rowNo=0
  foreach($line in Get-Content -LiteralPath $Path -Encoding UTF8){
    $rowNo++
    if([string]::IsNullOrWhiteSpace($line)){continue}
    $cells=$line.Split(',')
    if($cells.Count -ne $Cols){throw "$Path row $rowNo has $($cells.Count) columns, expected $Cols"}
    foreach($cell in $cells){
      $text=$cell.Trim()
      if($text -notmatch '^[+-]?[0-9]+$'){throw "$Path row $rowNo contains a non-integer"}
      $value=[long]::Parse($text,[Globalization.CultureInfo]::InvariantCulture)
      if($value -lt $Min -or $value -gt $Max){throw "$Path value $value is outside [$Min,$Max]"}
      $result.Add($value)
    }
  }
  if($result.Count -ne $Rows*$Cols){throw "$Path has $($result.Count) values, expected $($Rows*$Cols)"}
  return ,$result.ToArray()
}
$source=@{}
foreach($key in @('a_csv','b_csv','bias_csv','expected_csv')){
  $path=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $manifestPath) $spec.$key))
  if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing input CSV: $path"}
  $source[$key]=$path
}
$a=Read-IntCsv $source.a_csv $m $k -32768 32767
$b=Read-IntCsv $source.b_csv $k $n -32768 32767
$bias=Read-IntCsv $source.bias_csv $n 1 -2147483648 2147483647
$expected=Read-IntCsv $source.expected_csv $m $n -32768 32767
function Write-Hex([string]$Path,[long[]]$Values,[int]$Bits){
  $mask=[long]((1L -shl $Bits)-1)
  $width=[int]($Bits/4)
  $format='x'+$width
  $lines=foreach($value in $Values){([long]($value -band $mask)).ToString($format,[Globalization.CultureInfo]::InvariantCulture)}
  [IO.File]::WriteAllLines($Path,$lines,[Text.Encoding]::ASCII)
}
$outputs=@{
  'a_int16.mem'=@($a,16)
  'b_int16.mem'=@($b,16)
  'bias_int32.mem'=@($bias,32)
  'expected_int16.mem'=@($expected,16)
}
foreach($name in $outputs.Keys){Write-Hex (Join-Path $out $name) $outputs[$name][0] $outputs[$name][1]}
$sourceManifest=@{}
foreach($key in $source.Keys){$sourceManifest[$key]=@{path=$source[$key];sha256=(Get-FileHash -LiteralPath $source[$key] -Algorithm SHA256).Hash.ToLowerInvariant()}}
$prepared=@{}
foreach($name in $outputs.Keys){$path=Join-Path $out $name;$prepared[$name]=@{count=$outputs[$name][0].Count;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}}
$result=[ordered]@{format_version=1;dimensions=@{m=$m;k=$k;n=$n};out_shift=$shift;
  contract=@{input_dtype='int16';weight_dtype='int16';product_dtype='int32';accumulator_dtype='int48';
    bias_dtype='int32';output_dtype='int16';layout='row_major';rounding='nearest_ties_away';
    overflow='saturate';k_tile=32};source_manifest=$sourceManifest;prepared_files=$prepared}
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $out 'prepared_manifest.json') -Encoding UTF8
Write-Output "Prepared INT16 input M=$m K=$k N=$n shift=$shift at $out"
