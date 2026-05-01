<?php
require_once(dirname(__FILE__) . "/../../core/globalSettings.php");
// $this->guiId is only available when this file is included from inside an object;
// when hit directly via HTTP we have no class context, so fall back to gui_id from session/request.
$guiId = isset($this) && is_object($this) && isset($this->guiId)
    ? $this->guiId
    : ($_REQUEST['gui_id'] ?? Mapbender::session()->get('mb_user_gui') ?? '');
echo "<table width='100%' style='background-color:#e2e2e2'><tr align='center'><td><br><br><br><br><img alt='ajax-loader' src='../img/ajax-loader.gif'>"."&nbsp;&nbsp;&nbsp;&nbsp;"."<img alt='logo' src='../geoportal/geoportal_logo.png'>"."&nbsp;&nbsp;&nbsp;&nbsp;"."<img alt='ajax-loader' src='../img/ajax-loader.gif'></td></tr><tr align='center'><td><br><strong>"._mb('please wait ... ')."</strong></td></tr>"."<tr  align='center'><td><br>"._mb('Loading application: ')."" . $guiId . "</td></tr></table>";
?>
