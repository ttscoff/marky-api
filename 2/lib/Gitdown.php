<?php
/**
* Gitdown 
* Beautify Github Style Markdown Utilizing the Github v3 API
* (https://developer.github.com/v3/)
* Example:
* <code>
*      
*   $markdown = '```php $some_php = "Markdown"; ```';
* 	$formatted = Gitdown::pretty($markdown);
*
* </code>
* @author Jeremy M. Usher <jeremy@firefly.us>
* @copyright 2014 Jeremy M. Usher 
* @category Utilities
* @version 0.90
* @license http://opensource.org/licenses/MIT MIT License
*
*/
class Gitdown {


	const ENDPOINT = 'https://api.github.com/markdown';


	/**
	* Transform a markdown document into markdown/pygments ready HTML.
	* This API request is unauthenticated and currently limited 
	* by Github to 60 requests per hour.
	*
	* @param String $markdown
	* @return String HTML
	*/
	public static function pretty($markdown) {

		return self::post($markdown);
	}


	private static function post($content, $endpoint=self::ENDPOINT) {


        $ch = curl_init($endpoint);
        curl_setopt($ch, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
        curl_setopt($ch, CURLOPT_POST, 1);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER,1);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode(array('text'=>$content)));
        curl_setopt($ch, CURLOPT_USERAGENT,'Apollo Syntax Highlighter');
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, 1);
        curl_setopt($ch, CURLOPT_HTTPHEADER, array('Content-Type: application/json',
        					   'Accept: application/vnd.github.v3+json'));

        if( !($response = curl_exec($ch)) ) {

            throw new Exception("Bad Response from API." . print_r($response, true));
        }

        curl_close($ch);

        return $response;

	}




}
