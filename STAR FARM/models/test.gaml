/**
* Name: test
* Based on the internal empty template. 
* Author: Tri
* Tags: 
*/


model test

global{
	
	list<int> values <- [4,1,7,3,12,1,1,5,3];
}

experiment e1 type:gui virtual: true{
	output{
		display infos type: 2d virtual: true{
			chart name: "Chart" type: series{
				data "data" value: values;
			} 
		}
	}
}

experiment e2 type:gui parent: e1 virtual: true{
	output{
		display infos2 parent: infos virtual: true{
//			chart name: "Chart2" type: series{
//				data "data" value: values color: #green;
//			} 
		}
	}
}


experiment e3 type:gui parent: e2{
	output{
		display infos3 parent: infos virtual: false {}
	}
}

experiment e3b type:gui parent: e2{
	output{
		display infos3 parent: infos2 virtual: false {}
	}
	
}






