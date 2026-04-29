<?php
/*
 * Show list of publish available csw resources that can be used for remote searching
 */
require_once(dirname(__FILE__)."/../../core/globalSettings.php");
if (file_exists ( dirname ( __FILE__ ) . "/../../conf/remoteCsw.json" )) {
    $configObject = json_decode ( file_get_contents ( "../../conf/remoteCsw.json" ) );
}
$availableCsw = array();
if (isset ( $configObject ) && isset ( $configObject->available_services ) && count($configObject->available_services) != 0) {
    $availableCsw = $configObject->available_services;
}
if (!is_array($availableCsw) || count($availableCsw) === 0) {
    header('Content-Type: application/json');
    echo json_encode(array('catalogues' => array()));
    exit;
}
$sql = "SELECT cat_id, cat_title FROM cat WHERE cat_id in (" . implode(",", $availableCsw) . ");";
$res = db_query($sql);
$jsonOutput = new stdClass();
$jsonOutput->catalogues = array();
$numberOfCsw = 0;
while($row = db_fetch_array($res)){
    if (!isset($jsonOutput->catalogues[$numberOfCsw]) || !is_object($jsonOutput->catalogues[$numberOfCsw])) $jsonOutput->catalogues[$numberOfCsw] = new stdClass();
    $jsonOutput->catalogues[$numberOfCsw]->{'id'} = $row['cat_id'];
    $jsonOutput->catalogues[$numberOfCsw]->{'title'} = $row['cat_title'];
    $numberOfCsw++;
   }
$json = json_encode($jsonOutput);
header('Content-Type: application/json');
echo $json;
?>
