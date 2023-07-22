while ($true) {
    $APP_PID = "com.yourcompany.bundleid"
    
    $processId = $(adb shell pidof $APP_PID)

    if($processId)
    {
        Write-Output $(adb shell run-as $APP_PID "ls -l /proc/${processId}/fd | wc -l")
    }
    
    Start-Sleep 1
}