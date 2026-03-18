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
	map<string, rgb> practices_color<-[BAU_3S::#orange,OMRH::#green, BAU_2S::#pink, BAU_3S_sust::#blue] ;   
}

