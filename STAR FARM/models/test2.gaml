model STARFARM  

global{
	
	list<string> key_indicators <- ["Harvest","Profit","Crop area","Water consumption","Fertilizer consumption","Current year","Current season"];	
	list<string> chart_list <- key_indicators;
	string current_chart <- first(chart_list);

	init{
		write key_indicators;
	}
	
}
	
	
experiment test type:gui  {		
	parameter "Chart" var: current_chart init: "Total crop biomass per practice"  among: chart_list;	
}

