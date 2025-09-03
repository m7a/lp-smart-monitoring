<?php
define("MA_CONFIGURATION_FILE", "php_smartd_auswertung_conf.xml");
$start = microtime(true);
$return_value = 0;
setlocale(LC_ALL, "de_DE");
date_default_timezone_set("Europe/Berlin");

header("Content-Type: application/xhtml+xml; charset=UTF-8");
echo("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
 
<html xmlns="http://www.w3.org/1999/xhtml">
	<head>
		<title>Ma_Sys.ma PHP Smartd Auswertung</title>
		<style type="text/css">
			/* <![CDATA[ */
			h1, h2 { font-family: sans-serif; }
			p.error {
				color: #aa0000;
			}
			hr {
				border: none;
				border-top: 1px solid #bbbbbb;
				margin-top: 8px;
				margin-bottom: 8px;
				clear: both;
			}
			table {
				font-size: 68%;
				border-collapse: collapse;
				margin-bottom: 22px;
			}
			table tr td {
				padding: 2px;
				background-color: #eeeeee;
				color: #000000;
			}
			.unchanged_ok, .unchanged_almost_ok, .unchanged_nonzero, .changed_normal, 
			.changed_important, .changed_less_important {
				text-align: right;
			}
			table tr td.unchanged_ok           { background-color: #bbffbb; }
			table tr td.unchanged_almost_ok    { background-color: #ddffdd; }
			table tr td.unchanged_nonzero      { background-color: #ddeeff; }
			table tr td.changed_normal         { background-color: #ffeedd; }
			table tr td.changed_less_important { background-color: #ff70ff; }
			table tr td.changed_important      { background-color: #ff0000; }
			/* OPTIONAL FOR REALLY BIG MONITORS BUT NEEDS SOME FINETUNING... */
			div.package { float: left; margin-right: 20px; }
			/* ]]> */
		</style>
	</head>
	<body>
		<h1>Datenträger</h1>
		<hr />
<?php
function ma_err($err) {
	echo "\t\t<p class=\"error\">".$err."</p>";
}

function ma_main() {
	global $return_value;
	// Load configuration
	$conf = new DOMDocument();
	if(!$conf->load(MA_CONFIGURATION_FILE, LIBXML_DTDVALID | LIBXML_NOCDATA | LIBXML_NOENT)) {
		ma_err("Die angegebene Konfigurationsdatei konnte nicht geladen werden.");
		return;
	}
	if(!$conf->validate()) {
		ma_err("Die angegebene Konfigurationsdatei ist ungültig.");
		return;
	}
	// Load general configuration
	$general_configuration = array();
	$general_section = $conf->getElementsByTagName("general_configuration")->item(0)->getElementsByTagName("set");
	for($i = 0; $i < $general_section->length; $i++) {
		$assoc = $general_section->item($i);
		$general_configuration[$assoc->getAttribute("key")] = $assoc->getAttribute("val");
	}
	// Load devices
	$device_section = $conf->getElementsByTagName("devices")->item(0);
	$file_prefix = $device_section->getAttribute("table_prefix");
	$file_suffix = $device_section->getAttribute("table_suffix");
	$start_time = time() - 24 * 3600 * ((int)$device_section->getAttribute("days") + 1);
	//$start_time = date("Y-m-d", time() - 24 * 3600 * ((int)$device_section->getAttribute("days") + 1));
	$devices = $device_section->getElementsByTagName("device");
	for($i = 0; $i < $devices->length; $i++) {
		$device = $devices->item($i);
		echo("\t\t<div class=\"package\">\n");
		echo("\t\t\t<h2>".htmlspecialchars($device->hasAttribute("title") ? $device->getAttribute("title") : $device->getAttribute("table"))."</h2>\n");
		// Determine attribute names
		$attribute_names_assoc = array();
		$attribute_names = $device->getElementsByTagName("attribute");
		for($j = 0; $j < $attribute_names->length; $j++) {
			$cItem = $attribute_names->item($j);
			$attribute_names_assoc[$cItem->getAttribute("id")] = array(
				htmlspecialchars($cItem->getAttribute("title")),
				$cItem->getAttribute("raw") == "true" ? true : false,
				$cItem->getAttribute("chg"),
				(float)$cItem->getAttribute("fac"),
				(float)$cItem->getAttribute("add"),
			);
		}
		// Read and parse status CSV file
		$data_file = $file_prefix.$device->getAttribute("table").$file_suffix;
		if(!file_exists($data_file)) {
			ma_err("Tabelle <tt>".htmlspecialchars($data_file)."</tt> nicht vorhanden.");
			echo("</div>");
			continue;
		}
		$stream = fopen($data_file, "r");
		if(!$stream) {
			ma_err("Tabelle <tt>".htmlspecialchars($data_file)."</tt> konnte nicht gelesen werden.");
			echo("</div>");
			continue;
		}
		$aAssoc     = array();
		$skip       = true;
		$last_entry = null;
		$day        = null;
		$days       = array();
		while(($cline = fgetcsv($stream, 0, "\t")) !== false) {
			// Skip unwanted (old) entries.
			if($skip) {
				$cLineDate = substr($cline[0], 0, strlen($cline[0]) - 1);
				// I did not manage to find a solution to this on the net.
				$cDateParts = explode(" ", $cLineDate);
				$cYMD = explode("-", $cDateParts[0]);
				$cHMS = explode(":", $cDateParts[1]);
				$timestampThen = mktime($cHMS[0], $cHMS[1], $cHMS[2], $cYMD[1], $cYMD[2], $cYMD[0]);
				if($timestampThen >= $start_time) {
					$skip = false;
				} else {
					continue;
				}
			}
			// Determine wether we just went on to entries of another day
			$spcPos = strpos($cline[0], " ");
			$cDay = substr($cline[0], 0, $spcPos);
			// Only evaluate last entry of a day
			if($cDay != $day) {
				if($last_entry !== null) {
					$max = count($last_entry);
					for($j = 1; $j < $max; $j++) {
						$data = explode(";", $last_entry[$j]);
						$aAssoc[$data[0]][] = array($data[1], $data[2]);
					}
				}
				$days[] = date("d.m", strtotime($cDay)); // reformat to german date
				$day = $cDay;
			}
			$last_entry = $cline;
		}
		// TODO excactly as above... try to merge
		$max = count($last_entry);
		for($j = 1; $j < $max; $j++) {
			$data = explode(";", $last_entry[$j]);
			$aAssoc[$data[0]][] = array($data[1], $data[2]);
		}
		fclose($stream);
		echo("\t\t\t<table summary=\"Smart Attribute und Werte\">\n");
		echo("\t\t\t\t<tr><td>&#160;</td>");
		//foreach(array_reverse($days) as $day) {
		$first = true;
		foreach($days as $day) {
			// Skip the first day (required for correct colorization)
			if($first) {
				$first = false;
				continue;
			}
			echo("<td>".htmlspecialchars($day)."</td>");
		}
		echo("</tr>\n");
		foreach($aAssoc as $attribute => $values) {
			$aIndex = 0; // normalized value
			$title = $attribute;
			$handle = "important";
			$fac = 1;
			if(isset($attribute_names_assoc[$attribute])) {
				$aIndex = $attribute_names_assoc[$attribute][1] == false ? 0 : 1; // 1: raw value is to be evaluated.
				$title  = $attribute_names_assoc[$attribute][0];
				$handle = $attribute_names_assoc[$attribute][2];
				$fac    = $attribute_names_assoc[$attribute][3];
				$add    = $attribute_names_assoc[$attribute][4];
			}
			echo("\t\t\t\t<tr><td>".$title."</td>");
			$last_val = null;
			$class = null;
			//foreach(array_reverse($values) as $cValArray) {
			$first = true;
			$last_index = count($values);
			$c_index = 1;
			$checkdate = date($general_configuration["checkdate"]);
			$already_checked = file_get_contents($general_configuration["checkfile"]) == $checkdate ? true: false;
			foreach($values as $cValArray) {
				// Fine colorization
				// unchanged_ok better than unchanged_almost_ok better than unchanged_nonzero better than changed_normal better than changed_important
				$class = "unchanged_nonzero";
				if($cValArray[$aIndex] == 0 && $aIndex == 1) {
					$class = "unchanged_ok";
				} else if($aIndex == 0) {
					if($cValArray[$aIndex] == 100) {
						$class = "unchanged_ok";
					} else if($cValArray[$aIndex] > 100) {
						$class = "unchanged_almost_ok";
					}
				}
				if($last_val != null) {
					if($cValArray[$aIndex] != $last_val) {
						$class = "changed_".$handle;
						if($handle == "important") {
							$return_value = 1;
						} elseif($handle == "less_important" && $c_index == $last_index && !$already_checked) {
							file_put_contents($general_configuration["checkfile"], $checkdate);
							$return_value = 1;
						}
					}
				}
				// Skip the first day (required for correct colorization)
				if($first) {
					$first = false;
				} else {
					$facfmt = sprintf("%.0f", round($add + $cValArray[$aIndex] * $fac));
					echo("<td class=\"".$class."\">".$facfmt."</td>");
				}
				$last_val = $cValArray[$aIndex];
				$c_index++;
			}
			echo("</tr>\n");
		}
		echo("\t\t\t</table>\n");
		echo("\t\t</div>\n");
	}
}

ma_main();

?>
		<hr />
		<p>
			Ma_Sys.ma PHP Smartd Auswertung 1.0.1.4, Copyright (c) 2012, 2013, 2016 Ma_Sys.ma.<br />
			For further info send an e-mail to Ma_Sys.ma@web.de.
		</p>
		<hr />
		<p>&#916;t = <?php echo(round(microtime(true) - $start, 6)); ?>s</p>
	</body>
</html>
<!-- RETURNING <?php echo($return_value); ?> -->
<?php exit($return_value); ?>
