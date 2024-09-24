<?php
$last = explode(",", $_REQUEST['last']);

$links = array(
  'http://thesweetsetup.com/aaron-mahnkes-sweet-mac-setup/',
  'http://brettterpstra.com/2014/05/04/folderize-sync-nvalt-notes-to-nested-folders/',
  'http://daringfireball.net/2011/02/the_daily_wait',
  'http://www.engadget.com/2012/06/15/engadget-primed-nanometers/');
do {
  $link = array_rand($links,1);
} while (in_array("$link",$last));

if (count($last) == count($links) - 1)
  $link = false;

echo json_encode(array('num' => $link,'link' => $links[$link]));
?>
