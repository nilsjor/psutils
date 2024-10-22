Set-StrictMode -Off;

# bodge the ln command
$usage = @"
Usage: ln [OPTION]... TARGET LINK_NAME
  or:  ln [OPTION]... TARGET
In the 1st form, create a link to TARGET with the name LINK_NAME.
In the 2nd form, create a link to TARGET in the current directory.
Create hard links by default, symbolic links with --symbolic.
By default, each destination (name of new link) should not already exist.

  -f, --force                 remove existing destination files
  -s, --symbolic              make symbolic links instead of hard links
      --help                  display this help and exit
"@

$src = '
using System;
using System.Runtime.InteropServices;
public class kernel {
	[DllImport("kernel32.dll")]
	[return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.I1)]
	public static extern bool CreateSymbolicLink(string lpSymlinkFileName, string lpTargetFileName, uint dwFlags);

	[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Auto)]
	public static extern bool CreateHardLink(string lpFileName, string lpExistingFileName, IntPtr lpSecurityAttributes);
}'

function isadmin {
	$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
	$p = new-object System.Security.Principal.WindowsPrincipal $id
	$p.isinrole([security.principal.windowsbuiltinrole]::administrator)
}

function symlink($target, $link_name, $is_dir) {
	# CreateSymbolicLink:
	#     http://msdn.microsoft.com/en-us/library/aa363866.aspx
	$dwFlags = 0
	if($is_dir) { $dwFlags = 1 }

	$kernel = add-type $src -passthru
	$result = $kernel::createsymboliclink($link_name, $target, $dwFlags)

	if(!$result) { "failed!"; exit 1 } # mysterious
}

function hardlink($target, $link_name) {
	# CreateHardLink:
	#     http://msdn.microsoft.com/en-us/library/aa363860.aspx
	$kernel = add-type $src -passthru
	$result = $kernel::createhardlink($link_name, $target, [intptr]::zero)

	if(!$result) { "failed!"; exit 1 } # mysterious
}

$symbolic = $false
$force = $false
$target = $null
$link_name = $null
$is_dir = $false

foreach ($arg in $args) {
    if ($arg -like '-s*') {
        $symbolic = $true
        if ($arg -like '*f*') {
            $force = $true
        }
    } elseif ($arg -like '-f*') {
        $force = $true
        if ($arg -like '*s*') {
            $symbolic = $true
        }
    } elseif ($arg -like '--symbolic') {
        $symbolic = $true
    } elseif ($arg -like '--force') {
        $force = $true
    } elseif ($arg -like '--help') {
        $usage; exit 0
    } elseif (-not $target) {
        $target = $arg
    } elseif (-not $link_name) {
        $link_name = $arg
    }
}

if(!$target) { "ln: target is required"; $usage; exit 1 }
if(!$link_name) {
	# create link in working dir, with same name as target
	$link_name = "$pwd\$(split-path $target -leaf)"
} elseif(!([io.path]::ispathrooted($link_name))) {
	$link_name = "$pwd\$link_name"
}

if(!(test-path $target)) {
	"ln: failed to access '$target': No such file or directory"; exit 1
}

if(test-path $link_name) {
    if ($force) {
        Remove-Item -Force $link_name
    } else {
        "ln: failed to create link '$link_name': File exists"; exit 1
    }
}

$abstarget = "$(resolve-path $target)"
if([io.directory]::exists($abstarget)) {
	$is_dir = $true
}

if($abstarget -eq $link_name) {
	"ln: target and link_name are the same"; $usage; exit 1
}

if(!$symbolic -and $is_dir) {
	"ln: $target`: hard link not allowed for directory"; exit 1
}

if(!(isadmin)) {
	if(gcm 'sudo' -ea silent) {
		"ln: Must run elevated: try using 'sudo ln ...'."
	} else {
		if(gcm 'scoop' -ea silent) {
			"ln: Must run elevated: you can install 'sudo' by running 'scoop install sudo'."
		} else { "ln: Must run elevated" }
	}
	exit 1
}

if($symbolic) {
	symlink $target $link_name $is_dir
} else {
	hardlink $target $link_name
}

exit 0
