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
	map<string, rgb> practices_color<-["Business as usual"::rgb(198, 219, 239)-100,"AWD"::rgb(199, 233, 192)-100] ;   
}

