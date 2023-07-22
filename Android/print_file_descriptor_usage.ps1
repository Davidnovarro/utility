while ($true) {
    $APP_PID = "com.yourcompany.bundleid"    
    $processId = $(adb shell pidof $APP_PID)

    if($processId)
    {
        $usage = $(adb shell run-as $APP_PID "ls -l /proc/${processId}/fd | wc -l")
        Clear-Host
        Write-Output "File Descriptors: $usage"
    }else {
        Clear-Host
        Write-Output "App is not running ($APP_PID)"
    }
    
    Start-Sleep 1
}
