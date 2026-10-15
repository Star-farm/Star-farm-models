/**
* Name: Parameters
* Based on the internal empty template. 
* Author: patrick taillandier
* Tags: 
*/

model STARFARM

import "Constants.gaml"

global {
	map<string, rgb> category_color<-["Daily indicators"::rgb(243, 156, 18),"Year evolution" ::rgb(46, 204, 113),"Scale and time"::rgb(100, 100, 100)] ;   
	map<string, rgb> practices_color<-[BAU_3S::#orange,OMRH::#green, BAU_2S::#pink, BAU_3S_AWD::#blue, CUSTOM::#gray] ;   
	// Color mapping by active production type on the plot
	map<string, rgb> production_type_colors <- [PROD_RICE   :: rgb(46, 204, 113),  // Emerald green for Rice
   		 PROD_SHRIMP :: rgb(230, 126, 34),  // Coral / Orange for Shrimp (or rgb(52, 152, 219) for brackish cyan)
   		 PROD_FISH   :: rgb(41, 128, 185)   // Deep blue for Fish
	];
}

