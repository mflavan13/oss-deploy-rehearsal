# Authors the optionset/boolean columns the wedged source org's exporter silently
# dropped, injecting healthy attribute XML into customizations.xml.
# Value->label maps come from the app's generated models (the runtime source of truth).
# The two v1 zombies (refreshrununit.oss_objecttype, productcomponent.oss_componenttype)
# are DELIBERATELY omitted - the app reads only the v2 columns, which exported healthy.
#
# PIPELINE CONTEXT: this script is step (b) of the zip-patch pipeline in the
# docs/PORT.md 2026-07-20 AMENDMENT ("solution export is POISONED on the source
# org; use the zip-patch pipeline") - read that box before running.
# PROVENANCE: it authors the ~24 optionset/boolean columns the wedged exporter
# silently dropped, sourcing value->label maps from the generated-model constant
# blocks in src/generated/models/*Model.ts (the runtime source of truth).
# POWERSHELL GOTCHA (bit twice during the live run): [ordered]@{} /
# OrderedDictionary with INTEGER keys treats indexer access as POSITIONAL, not
# key-based - build option maps with .Add() and iterate them with
# .GetEnumerator(); never index an int-keyed ordered dictionary directly.
# PARAMETERIZED (Phase 18, T9 / D-14): the three port-time hardcoded paths are now a
# [CmdletBinding()] param() block so a GHA runner can call this headless with no tenant.
# The $specs 25-column contract and the New-AttributeNode logic are UNCHANGED - a
# parameterized run authors byte-identically to scripts/port/fixtures/
# customizations.authored-baseline.xml (proven by author-missing-columns.Tests.ps1).
# IDEMPOTENT: a re-run over already-authored XML SKIPs every spec and prints "AUTHORED: 0"
# - the SKIP-if-present guard (below) makes this safe to re-run at any time.
# USAGE (headless, no tenant):
#   ./author-missing-columns.ps1 -XmlPath <extracted customizations.xml>              # author in place
#   ./author-missing-columns.ps1 -SolutionZip out/src.zip -OutZip out/patched.zip     # extract->author->rezip
#   ./author-missing-columns.ps1 -XmlPath <file> -WhatIf                              # dry run, no write
[CmdletBinding()]
param(
    # An already-extracted customizations.xml, authored IN PLACE. Provide this OR -SolutionZip.
    # The Pester byte-identical proof drives this path directly.
    [string]$XmlPath,

    # A solution .zip whose customizations.xml is extracted, authored, then re-zipped to -OutZip
    # (the GHA-runner path). Ignored when -XmlPath is supplied.
    [string]$SolutionZip,

    # Generated-model dir with the *Model.ts value->label constant blocks (the runtime source of
    # truth). Repo-relative default (scripts/port -> ../../src/generated/models) so the script is
    # not absolute-path bound.
    [string]$ModelsDir = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'src/generated/models'),

    # Destination zip for the -SolutionZip path. Required only when -SolutionZip is used.
    [string]$OutZip,

    # Dry run: run the whole authoring transform in memory, print the AUTHORED count, write NOTHING
    # and touch NO network (headless posture for a GHA runner with no tenant).
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'

# ---- resolve the working customizations.xml (direct -XmlPath, or extracted from -SolutionZip) ----
$extractRoot = $null
if (-not $XmlPath) {
  if (-not $SolutionZip) { throw 'Provide -XmlPath (extracted customizations.xml) or -SolutionZip.' }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("authcols-" + [guid]::NewGuid().ToString('N'))
  [System.IO.Compression.ZipFile]::ExtractToDirectory($SolutionZip, $extractRoot)
  $XmlPath = Join-Path $extractRoot 'customizations.xml'
  if (-not (Test-Path $XmlPath)) { throw "customizations.xml not found inside $SolutionZip" }
}
[xml]$x = Get-Content $XmlPath

# ---- column specs: entity -> attribute -> kind + options (value=label) ----
# Choice values verified against src/generated/models/*Model.ts constant blocks.
$P = 124860000  # publisher option-value base
$specs = @(
  @{ e='oss_codereview';            a='oss_changetype';  kind='picklist'; opts=[ordered]@{ ($P+0)='Enhancement'; ($P+1)='NewSolution'; ($P+2)='BugFix'; ($P+3)='EmergencyFix' } }
  @{ e='oss_codereview';            a='oss_status';      kind='picklist'; opts=[ordered]@{ ($P+0)='Requested'; ($P+1)='InReview'; ($P+2)='Approved'; ($P+3)='ChangesRequested'; ($P+4)='Rejected' } }
  @{ e='oss_enhancement';           a='oss_priority';    kind='picklist'; opts=[ordered]@{ ($P+0)='High'; ($P+1)='Medium'; ($P+2)='Low'; ($P+3)='TBD' } }
  @{ e='oss_enhancement';           a='oss_status';      kind='picklist'; opts=[ordered]@{ ($P+0)='Backlog'; ($P+1)='InProgress'; ($P+2)='Completed'; ($P+3)='Cancelled' } }
  @{ e='oss_product';               a='oss_lifecyclestate'; kind='picklist'; opts=[ordered]@{ ($P+0)='Active'; ($P+1)='Deprecated'; ($P+2)='Decommissioned' } }
  @{ e='oss_statushistory';         a='oss_itemtype';    kind='picklist'; opts='FROM_MODEL:Oss_statushistoriesModel:Oss_statushistoriesoss_itemtype' }
  @{ e='oss_refreshrununit';        a='oss_status';      kind='picklist'; opts='FROM_MODEL:Oss_refreshrununitsModel:Oss_refreshrununitsoss_status' }
  @{ e='oss_metricdaily';           a='oss_metrictype';  kind='picklist'; opts='FROM_MODEL:Oss_metricdailiesModel:Oss_metricdailiesoss_metrictype' }
  @{ e='oss_metricdaily';           a='oss_objecttype';  kind='picklist'; opts='FROM_MODEL:Oss_metricdailiesModel:Oss_metricdailiesoss_objecttype' }
  @{ e='oss_metricdaily';           a='oss_capturepath'; kind='picklist'; opts=[ordered]@{ ($P+0)='Import'; ($P+1)='Refresh' } }
  @{ e='oss_invapp';                a='oss_capturepath'; kind='picklist'; opts=[ordered]@{ ($P+0)='Import'; ($P+1)='Refresh' } }
  @{ e='oss_invapp';                a='oss_insolution';  kind='bit' }
  @{ e='oss_invconnectionreference';a='oss_capturepath'; kind='picklist'; opts=[ordered]@{ ($P+0)='Import'; ($P+1)='Refresh' } }
  @{ e='oss_invconnectionreference';a='oss_insolution';  kind='bit' }
  @{ e='oss_invconnectionreference';a='oss_isbound';     kind='bit' }
  @{ e='oss_invcustomconnector';    a='oss_capturepath'; kind='picklist'; opts=[ordered]@{ ($P+0)='Import'; ($P+1)='Refresh' } }
  @{ e='oss_invcustomconnector';    a='oss_insolution';  kind='bit' }
  @{ e='oss_invcustomconnector';    a='oss_ismanaged';   kind='bit' }
  @{ e='oss_invflow';               a='oss_capturepath'; kind='picklist'; opts=[ordered]@{ ($P+0)='Import'; ($P+1)='Refresh' } }
  @{ e='oss_invflow';               a='oss_insolution';  kind='bit' }
  @{ e='oss_invsolution';           a='oss_capturepath'; kind='picklist'; opts=[ordered]@{ ($P+0)='Import'; ($P+1)='Refresh' } }
  @{ e='oss_invsolution';           a='oss_insolution';  kind='bit' }
  @{ e='oss_invsolution';           a='oss_ismanaged';   kind='bit' }
  @{ e='oss_productcomponent';      a='oss_hybridowned'; kind='bit' }
  @{ e='oss_reviewchecklistitem';   a='oss_ischecked';   kind='bit' }
)

# ---- resolve FROM_MODEL specs by parsing the generated model constant blocks ----
# $ModelsDir is now a param (repo-relative default). Keep it pointed at the generated
# model dir - those *Model.ts constant blocks are the runtime value->label source of truth.
$modelsDir = $ModelsDir
foreach ($s in $specs) {
  if ($s.opts -is [string] -and $s.opts -like 'FROM_MODEL:*') {
    $parts = $s.opts -split ':'
    $file = "$modelsDir/$($parts[1]).ts"
    $constName = $parts[2]
    $txt = Get-Content $file -Raw
    if ($txt -notmatch "export const $constName = \{([\s\S]*?)\} as const") { throw "Const $constName not found in $file" }
    $body = $Matches[1]
    $opts = [ordered]@{}
    foreach ($m in [regex]::Matches($body, "(\d+):\s*'([^']*)'")) { $opts.Add([int]$m.Groups[1].Value, $m.Groups[2].Value) }
    if ($opts.Count -eq 0) { throw "No options parsed for $constName" }
    $s.opts = $opts
  }
}

# ---- templates from healthy exported nodes ----
$prodEnt = $x.SelectNodes('//Entities/Entity') | Where-Object { $_.Name.InnerText -ieq 'oss_product' }
$picklistTemplate = ($prodEnt.SelectNodes('.//attributes/attribute') | Where-Object { $_.SelectSingleNode('./LogicalName').InnerText -eq 'oss_userscope' })
if (-not $picklistTemplate) { throw 'UserScope picklist template not found' }
$rciEnt = $x.SelectNodes('//Entities/Entity') | Where-Object { $_.Name.InnerText -ieq 'oss_reviewchecklistitem' }
$bitTemplate = ($rciEnt.SelectNodes('.//attributes/attribute') | Where-Object { $_.SelectSingleNode('./LogicalName').InnerText -eq 'oss_not_applicable' })
if (-not $bitTemplate) { throw 'Boolean (bit) template oss_not_applicable not found' }
"TEMPLATES OK: picklist=oss_userscope, bit=oss_not_applicable"

function New-AttributeNode($doc, $template, $entityLogical, $attrLogical, $kind, $opts) {
  $node = $template.CloneNode($true)
  $displayText = ($attrLogical -replace '^oss_','')
  $displayText = $displayText.Substring(0,1).ToUpper() + $displayText.Substring(1)
  $node.SetAttribute('PhysicalName', $attrLogical)
  $node.SelectSingleNode('./Name').InnerText = $attrLogical
  $node.SelectSingleNode('./LogicalName').InnerText = $attrLogical
  # display names (attribute-level)
  foreach ($dn in $node.SelectNodes('./displaynames/displayname')) { $dn.SetAttribute('description', $displayText) }
  # descriptions: strip to avoid stale template text
  $desc = $node.SelectSingleNode('./Descriptions'); if ($desc) { [void]$node.RemoveChild($desc) }
  $os = $node.SelectSingleNode('.//optionset')
  if (-not $os) { throw "Template for $kind lacks optionset" }
  $os.SetAttribute('Name', "${entityLogical}_${attrLogical}")
  foreach ($dn in $os.SelectNodes('./displaynames/displayname')) { $dn.SetAttribute('description', $displayText) }
  if ($kind -eq 'picklist') {
    # rebuild options from spec
    $optsParent = $os.SelectSingleNode('./options')
    while ($optsParent.HasChildNodes) { [void]$optsParent.RemoveChild($optsParent.FirstChild) }
    foreach ($entry in $opts.GetEnumerator()) {
      $o = $doc.CreateElement('option')
      $o.SetAttribute('value', [string]$entry.Key)
      $o.SetAttribute('IsHidden', '0')
      $labels = $doc.CreateElement('labels'); $label = $doc.CreateElement('label')
      $label.SetAttribute('description', [string]$entry.Value); $label.SetAttribute('languagecode', '1033')
      [void]$labels.AppendChild($label); [void]$o.AppendChild($labels); [void]$optsParent.AppendChild($o)
    }
  }
  # bit template keeps its cloned 1/0 options + labels as-is
  return $node
}

$added = 0
foreach ($s in $specs) {
  $ent = $x.SelectNodes('//Entities/Entity') | Where-Object { $_.Name.InnerText -ieq $s.e }
  if (-not $ent) { throw "Entity $($s.e) not in export" }
  $attrsParent = $ent.SelectSingleNode('.//attributes')
  $exists = $attrsParent.SelectNodes('./attribute') | Where-Object { $_.SelectSingleNode('./LogicalName').InnerText -eq $s.a }
  if ($exists) { "SKIP (already present): $($s.e).$($s.a)"; continue }
  $tmpl = if ($s.kind -eq 'picklist') { $picklistTemplate } else { $bitTemplate }
  $node = New-AttributeNode $x $tmpl $s.e $s.a $s.kind $s.opts
  [void]$attrsParent.AppendChild($node)
  $added++
}
"AUTHORED: $added attributes"
if ($WhatIf) {
  "WHATIF: no file written; verifying the in-memory transform (headless dry run)"
  $v = $x
} else {
  $x.Save($XmlPath)
  [xml]$v = Get-Content $XmlPath
}

# ---- verification pass: reload (or in-memory under -WhatIf), re-check ----
$badLabels = 0
foreach ($opt in $v.SelectNodes('//option')) {
  $lbl = $opt.SelectSingleNode('./labels/label')
  if (-not $lbl -or [string]::IsNullOrWhiteSpace($lbl.GetAttribute('description'))) { $badLabels++ }
}
"LABEL-LESS OPTIONS AFTER AUTHORING: $badLabels"
foreach ($s in $specs) {
  $ent = $v.SelectNodes('//Entities/Entity') | Where-Object { $_.Name.InnerText -ieq $s.e }
  $hit = $ent.SelectNodes('.//attributes/attribute') | Where-Object { $_.SelectSingleNode('./LogicalName').InnerText -eq $s.a }
  if (-not $hit) { "STILL MISSING: $($s.e).$($s.a)" }
}
"VERIFY DONE"

# ---- re-zip the authored tree back to -OutZip (the GHA-runner path) ----
if ($extractRoot -and -not $WhatIf) {
  if (-not $OutZip) { throw '-SolutionZip requires -OutZip.' }
  if (Test-Path $OutZip) { Remove-Item $OutZip -Force }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::CreateFromDirectory($extractRoot, $OutZip)
  "REZIPPED: $OutZip"
}
