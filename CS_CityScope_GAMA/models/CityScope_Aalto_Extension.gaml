/***
* Name: CityScope_ABM_Aalto
* Author: Ronan Doorley and Arnaud Grignard
* Description: This is an extension of the orginal CityScope Main model.
* Tags: Tag1, Tag2, TagN
***/

model CityScope_ABM_Aalto

import "CityScope_main.gaml"

global{
	//GIS folder of the CITY	
	string cityGISFolder <- "./../includes/City/otaniemi";	
	
	// Variables used to initialize the table's grid position.
	float angle <- -9.74;
	point center <- {1600, 1000};
	float brickSize <- 24.0;
	float cityIOVersion<-2.1;
	bool initpop <-false;
	
	//	city_io
	string CITY_IO_URL <- "https://cityio.media.mit.edu/api/table/cs_aalto_2";
	// Offline backup data to use when server data unavailable.
	string BACKUP_DATA <- "../includes/City/otaniemi/cityIO_Aalto.json";
	
    //Sliders that dont exisit in Aalto table and are only used in version 1.0 
	int	toggle1 <- 2;
	int	slider1 <-2;
	// TODO: Hard-coding density because the Aalto table doesnt have it.
	list<float> density_array<-[1.0,1.0,1.0,1.0,1.0,1.0];
	
	// TODO: mapping needs to be fixed for Aalto inputs
	map<int, list> citymatrix_map_settings <- [-1::["Green", "Green"], 0::["R", "L"], 1::["R", "M"], 2::["R", "S"], 3::["O", "L"], 4::["O", "M"], 5::["O", "S"], 6::["A", "Road"], 7::["A", "Plaza"], 
		8::["Pa", "Park"], 9::["P", "Parking"], 20::["Green", "Green"], 21::["Green", "Green"]
	]; 
	

	// Babak dev:
	int max_walking_distance <- 300 	min:0 max:3000	parameter: "maximum walking distance form parking:" category: "people settings";
	int number_of_people <- 3500 min:0 max: 5000 parameter:"number of people in the simulation" category: "people settings";
	float min_work_start <- 8.0;
	float max_work_start <- 10.0;
	float min_work_end <- 17.0;
	float max_work_end <- 18.0;
	
	graph car_road_graph;
	graph pedestrian_road_graph;
	
	file parking_footprint_shapefile <- file(cityGISFolder + "/parking_footprint.shp");
	file roads_shapefile <- file(cityGISFolder + "/roads.shp");
	file campus_buildings <- file(cityGISFolder + "/Campus_buildings.shp");
	
	float step <- 30 #sec;
	int current_time update: (360 + time / #mn) mod 1440;
	
	//checking time
	int clock_display;
	reflex clock_Min when:current_time != clock_display {clock_display <- current_time ; write(string(int(current_time/60)) + ":" + string(current_time mod 60) ) ;
	}
	
	
	//reflex clock_Hour when:0=0 {write(current_time);}
	
	
	geometry shape <- envelope(bound_shapefile);
	
	
	string pressure_record <- "time,";
	string capacity_record <- "time,";
	parking recording_parking_sample;
	list<parking> list_of_parkings;
	float total_weight;
	
	// INITIALIZATION:
	
	init {
		create parking from: parking_footprint_shapefile with: [ID::int(read("Parking_id")),capacity::int(read("Capacity")),total_capacity::int(read("Capacity")), excess_time::int(read("time"))];
		list_of_parkings <- list(parking);
		

		create Aalto_buildings from: campus_buildings with: [usage::string(read("Usage")), scale::string(read("Scale")), weight::float(read("Weight"))]{
			if usage = "O"{
				color <- 	rgb(200,140,0,70);
				
			}
			total_capacity <- int(weight * number_of_people)+1;
			capacity <- int(weight * number_of_people)+1;
		}
		
		total_weight <- sum(Aalto_buildings collect each.weight);
		write(total_weight);
		create car_road from: roads_shapefile;
		car_road_graph <- as_edge_graph(car_road);
		
		
		create aalto_people number: number_of_people {
			location <- {0,0,0};
			time_to_work <- int((min_work_start + rnd(max_work_start - min_work_start))*60);
			time_to_sleep <-int((min_work_end + rnd(max_work_end - min_work_end))*60);
			objective <- "resting";
		}
		
		do creat_headings_for_csv;


	}

	// DATA RECOD`RDING SECTION:
	
	int day_counter <- 1;
	string pressure_csv_path <- "../results/";
	string capacity_csv_path<- "../results/";
	
	action record_parking_attribute{
		pressure_record <- pressure_record + current_time;
		capacity_record <- capacity_record + current_time;
				
		loop a from: 0 to: length(list_of_parkings)-1	 { 
			recording_parking_sample <-list_of_parkings[a];
			pressure_record <- pressure_record + list_of_parkings[a].pressure + "," ;
			capacity_record <- capacity_record + list_of_parkings[a].vacancy + "," ;
		}	
		pressure_record <- pressure_record + char(10);
		capacity_record <- capacity_record + char(10);
	}
	action creat_headings_for_csv {
		loop b from: 0 to: length(list_of_parkings)-1	 { 
			pressure_record <- pressure_record + list_of_parkings[b].ID + "," ;
			capacity_record <- capacity_record + list_of_parkings[b].ID + "," ;
		}		
		pressure_record <- pressure_record + char(10);
		capacity_record <- capacity_record + char(10);
	}

	reflex save_the_csv when: current_time = 0{
		// TODO: just for testing, it should be removed later
		do pause; 
		
		save string(pressure_record) to: pressure_csv_path + string(#now, 'yyyyMMdd- H-mm - ') + "pressure" + day_counter + ".csv"  type:text ;
		save string(capacity_record) to: pressure_csv_path + string(#now, 'yyyyMMdd- H-mm - ') + "capacity" + day_counter + ".csv"  type:text ;
	}
	reflex time_to_record_stuff when: current_time mod 1 = 0{
		do record_parking_attribute;
	}
	
	// USER INTERACTION SECTION:
	
	map<string,unknown> my_input_capacity; 
	map my_agent_type;
	point target;
	action create_agents 
	{
		target <- #user_location;
		my_agent_type <- user_input("please enter the agent type: [1 = parking, 2 = Residential, 3 = Office]", ["type" :: 1]);

		write(target);
		if my_agent_type at "type" = 1 {
			do create_user_parking(target);
		}
		else if my_agent_type at "type" = 2{
			do create_user_residential(target);
		}
		else if my_agent_type at "type" = 3{
			do create_user_office(target);
		}
		else {
			write("this type of agent does not exist");
		}

	}
	
	action create_user_parking(point target_location){
		my_input_capacity <- user_input("Please specify the parking capacity", "capacity" :: 100);
		create parking number:1 with:(location: target_location) {
			capacity <- int(my_input_capacity at "capacity") ;
			total_capacity <-  int(my_input_capacity at "capacity");
			//vacancy <- (int(my_input_capacity at "capacity")/int(my_input_capacity at "capacity"));
			shape <- square(20);
			color <- #red;
			list_of_parkings <- list(parking);
			write("A parking was created with capacity of "+ char(10) + string(capacity) + char(10) + "and total capacity of " + char(10)+ string(total_capacity));
		}
		
	
	}
	
	action create_user_residential(point target_location){
		my_input_capacity <- user_input("Please specify the count of people living in the building", "capacity" :: 100);
		create Aalto_buildings number:1 with:(location: target_location ) {
			capacity <- int(my_input_capacity at "capacity");
			usage <- "R";
			shape <- polygon([target_location + {-10,-10},target_location + {-10,10},target_location + {10,-10},target_location + {10,10}]);		
			write("A building was constructed and count of dwellers are: " + char(10) + string(capacity));
		}

	}
	
	action create_user_office(point target_location){
		my_input_capacity <- user_input("Please specify the amount of people work at the office", "capacity" :: 100);
		create Aalto_buildings number:1 with:(location: target_location) {
			capacity <- int(my_input_capacity at "capacity");
			usage <- "O";
			shape <- polygon([target_location + {-10,-10},target_location + {-10,10},target_location + {10,-10},target_location + {10,10}]);
			write("A building was constructed and count of employees are: " + char(10) + string(capacity));
		}

	}



}




species Aalto_buildings parent:building schedules:[] {
	string usage;
	string scale;
	rgb color <- rgb(150,150,150,20);
	aspect base {
		draw shape color: color empty: true depth:  (total_capacity / 5);
	}
	int capacity;
	int total_capacity;
	float weight;
}

species parking {
	int capacity;
	int ID;
	int total_capacity;
	int excess_time <- 600;
	int pressure <- 0 ;
	//TODO: This should be fixed, for now it prevents division by zero
	float vacancy <- (capacity/(total_capacity + 0.0001)) update: (capacity/(total_capacity + 0.0001) );
	aspect Envelope {
		draw shape color: rgb(200 , 200 * vacancy, 200 * vacancy) ;
	}
	aspect pressure {
		draw circle(5) depth:pressure color: #orange;
	}
	
	reflex reset_the_pressure when: current_hour = max_work_start * 60{
		pressure <- 0 ;
	}
}

species aalto_people parent:people skills: [moving] {
	
	Aalto_buildings working_place;
	bool driving_car <- true;
	bool mode_of_transportation_is_car <- true;
	
	int time_to_work;
	int time_to_sleep;
	
	list<parking> list_of_available_parking;

	point the_target_parking;
	parking chosen_parking;
	string objective;
	point the_target <- nil;
	
	rgb color <- #red ;
	
	// ----- ACTIONS
	action create_list_of_parkings{
		list_of_available_parking <- sort_by(parking where (distance_to(each.location, working_place) < max_walking_distance  ),distance_to(each.location, working_place));
	}
	
	action find_living_place {
		living_place <- one_of(shuffle(Aalto_buildings where (each.usage = "R" )));
	}
	
	
	action park_the_car(parking target_parking) {
		target_parking.capacity <- target_parking.capacity -1;
	}
	
	action take_the_car(parking target_parking) {
		target_parking.capacity <- target_parking.capacity +1;
	}
	
	
	action distribution_by_weight (Aalto_buildings chosen_working_space) {
		chosen_working_space.capacity <- chosen_working_space.capacity -1 ;
	}
	
	action choose_working_place {
		working_place <- one_of(shuffle(Aalto_buildings where ((each.usage = "O" ) and (each.capacity > 0)) ) );
		do distribution_by_weight (working_place);
	}
	
	action Choose_parking {
		do create_list_of_parkings;
		chosen_parking <- one_of(list_of_available_parking where (
											(each.capacity 		> 0) and 
											(each.excess_time 	> (time_to_work - time_to_sleep) 
											))
		);
		the_target_parking <- any_location_in(chosen_parking);		
	}
	// ----- REFLEXES 	
	reflex time_to_go_to_work when: current_time = time_to_work and objective = "resting" {
		do find_living_place;
		
		location <- any_location_in(living_place);
		
		do choose_working_place;
		if (mode_of_transportation_is_car = true) {
			do Choose_parking;
			the_target <- any_location_in(working_place);
			objective <- "working";
		}	
		
		else {
			the_target <- any_location_in(working_place);
			objective <- "working";
		}
	}
	
	reflex time_to_go_home when: current_time = time_to_sleep and objective = "working" {
		objective <- "resting";
		the_target <- any_location_in(living_place);
		do find_living_place;
	}
	
	reflex change_mode_of_transportation when: location = the_target_parking {
		
		if chosen_parking.capacity > 0 and objective = "working"{
			driving_car <- false;
			do park_the_car(chosen_parking);
		}
		else if objective = "resting" and driving_car = false{
			driving_car <- true;
			do take_the_car(chosen_parking);

		}
		
		else {
			chosen_parking.pressure <- chosen_parking.pressure  + 1;
			do Choose_parking;
		}
	}

	reflex move when: the_target != nil {
		if (driving_car = true){
			if (objective = "working"){
				do goto target: the_target_parking on: car_road_graph  speed: (1 + rnd(0,5)#km / #h);
			}
			else{
				do goto target: the_target on: car_road_graph speed: (1 + rnd(0,5)#km / #h);
			}
		}
		else {
			if (objective = "working"){
				do goto target: the_target on: car_road_graph speed: (0.1 + rnd(0,5) #km / #h);
			}
			else {
				do goto target: the_target_parking on: car_road_graph speed: (0.1 + rnd(0,5)#km / #h);
			}
		}
		
      	if the_target = location {
        	the_target <- nil ;
		}
	}
	
	
	
	aspect base {
		if driving_car = true {
			draw circle(2) color:#cornflowerblue;
		} else{
			draw square(2) color:#lightsalmon;
		}
		
	}
}

// ----------------- ROADS SPECIES ---------------------

species car_road schedules:[]{
	aspect base{
		draw shape color: rgb(50,50,50) width:2;
	}
}




// ----------------- EXPREIMENTS -----------------
experiment test type: gui {
	float minimum_cycle_duration <- 0.01;
	output {

		display charts {
			chart "parking vacancy" size: {1 , 0.5} type: series{
				datalist list(parking)
				value: list((parking collect (1-each.vacancy)))
				marker: false
				style: spline;
			} 
			chart "total parking vacancy" size: {1 , 0.5}  position: {0,0.5}type: series{
				data "Total Parking Vacancy (%)"
				value: mean(list(parking) collect each.vacancy)
				marker: false
				style: spline;
				
			} 
		}
		display pie_charts {
			chart "found suitable parking (%)" size:{0.3 , 0.5} position: {0,0} type:pie{
				data "Parking found"value: list(aalto_people) count (each.chosen_parking != nil) color:#chartreuse;
				data "Parking Not found"value: list(aalto_people) count (each.chosen_parking = nil) color:#coral;
			}
			chart "Count of parkings with capacity" size:{0.3 , 0.5} position: {0.3,0} type:pie{
				data "Parkings with remaining capacity"value: list(parking) count (each.vacancy != 0) color:#chartreuse;
				data "Parkings with Full capacity"value: list(parking) count (each.vacancy = 0) color:#coral;
			}
			chart "total remaining capacity" size:{0.3 , 0.5} position: {0.6,0} type:pie{
				data "vacant (%)"value: mean(list(parking) collect each.vacancy) color:#chartreuse;
				data "Full (%)"value: 1 - mean(list(parking) collect each.vacancy) color:#coral;
			}
			chart "found suitable parking (%)" size:{1 , 0.5} position: {0,0.5} type:series{
				data "Parking found"value: list(aalto_people) count (each.chosen_parking != nil) 
				color:#chartreuse
				marker: false;
			}
		}
				display test type:opengl background: #black{
			species car_road aspect: base ;
			// species pedestrian_road aspect: base ;
			species parking aspect: Envelope ;
			species parking aspect: pressure;
			species Aalto_buildings aspect:base;
			species aalto_people aspect:base;
			event 'c' action: create_agents;
		}
	}
}

