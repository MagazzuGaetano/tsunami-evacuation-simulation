;;;;;                                                             ;;;;
;;;;; This model simulates a tsunami evacuation scenario with     ;;;;
;;;;; capability of adding vertical evaucation shelters and       ;;;;
;;;;; simulating transportation network damage and road closures. ;;;;
;;;;; This model is developed by Alireza Mostafizi and under      ;;;;
;;;;; direct supervision of Dr. Haihzong Wang, Dr. Dan Cox, and   ;;;;
;;;;; Dr. Lori Cramer from Oregon State University. Tsunami       ;;;;
;;;;; inundations are modeled by Dr. Hyoungsu Park. If you use    ;;;;
;;;;; this model to any extent, we ask you to cite our relevant   ;;;;
;;;;; publications listed in the Readme file of the repository.   ;;;;
;;;;;                                                             ;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;; EXTENSIONS ;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

extensions [
  gis   ; the GIS extension is required to load the 1. transportation network
        ;                                           2. shelter locations
        ;                                       and 3. population distribution
  csv   ; the CSV extension is required to read the tsunami inundation file
  table
  palette
  profiler
]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;; BREEDS ;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

breed [ residents resident]              ; the evacuees before they make it to the transportation network
breed [ pedestrians pedestrian ]         ; a resident will turn to a pedestrian (after they make it to the transportation network) if they decided to walk to the shelters
breed [ cars car ]                       ; a resident will turn to a car (after they make it to the transportation network) if they decided to drive to the shelters
breed [ intersections intersection ]     ; intersections are treated as agents
directed-link-breed [ roads road ]       ; roads are trated as directed links between the intersection (e.g, two directed links between a pair of intersections if the road is two-way)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;; VARIABLES ;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

patches-own [    ; the variables that patches own
  depth          ; current tsunami depth
  depths         ; sequence of tsunami depths over time
  max_depth      ; maximum depth of tsunami over time at the end of simulation
]

residents-own [  ; the variables that residents own
  init_dest      ; initial destination, the closest intersection to the agent at the start of simulation
  reached?       ; true if the agent is reached to the init_dest and ready to turn to pedestrian or car, false if not
  current_int    ; current/previous intersection of an agent, 0 if none
  moving?        ; true if the agent is moving, false if not
  evacuated?     ; true if an agent is evacuated, either in a shelter or outside of the shelter
  dead?          ; true if an agent is dead and caught by the tsunami
                 ; if the simulation is ended and the agent is not caught by the tsunami
  speed          ; speed of the agent, measured in patches per tick
  decision       ; the agents decision code: 1 for Hor Evac on foot
                 ;                           2 for Hor Evac by Car
                 ;                           3 for Ver Evac on foot
                 ;                           4 for Ver Evac by Car
  miltime        ; the agents milling time (preparation time before the evacuation starts) referenced from the earthquake
                 ; measureed in seconds
  time_in_water  ; time that the agent has been in the water in seconds
]

roads-own [        ; the variables that roads own
  crowd            ; number of people on foot on each link at any time
  traffic          ; number of cars on each link at any time
  mid-x            ; xcor of the middle point of a link, in patches
  mid-y            ; ycor of the middle point of a link, in patches
  car_mean_speed
  ped_mean_speed

  ;; flow analysis
  car-in-h             ; headways list
  car-out-h            ; headways list
  car-in-t             ; elapsed time for headway
  car-out-t

  ped-flow

  casualties
]

intersections-own [ ; the variables that intersections own
  shelter?          ; true if there is a shelter at an interseciton, flase if not
  shelter_type      ; string representing the type of the shelter, 'Hor' for horizontal
                    ;                                            , 'Ver' for vertical
  id                ; a unique id associated to each intersection (0 to number of intersections - 1)
  previous          ; for calculating the shortest path from each intersection to the a shelter (A* Alg)
  fscore            ; for calculating the shortest path from each intersection to the a shelter (A* Alg)
  gscore            ; for calculating the shortest path from each intersection to the a shelter (A* Alg)
  ver-path          ; best path from an intersection to the vertical shelter (list of intersection 'who's)
  hor-path          ; best path from an intersection to the horizontal shelter (list of intersection 'who's)
  evacuee_count     ; the number of agents that are evacuated in an intersection, if there is a shelter in it
  crossing_counts   ; (a, b): [car1, car2], (b, a): [], (a, c): [car3]
  crossroad?        ;
  arrival-queue
  crossing-cars    ; cars to be waited
  stops

  ; analysis
  car-delay
  ped-in-flow
  ped-out-flow
  car-in-flow
  car-out-flow
  evacuee_list
  car-avg_ev_times
  ped-avg_ev_times
]


pedestrians-own [; the variables that pedestrians own
  id             ; resident id
  current_int    ; current/previous intersection of an agent, 0 if none
  shelter        ; 'who' of the intersection that the agent is heading to (its shelter)
                 ; -1 if there is none due to disconnectivity in the network
  next_int       ; the next intersection an agent is heading towards
  moving?        ; true if the agent is moving, false if not (e.g., turning at intersection)
  evacuated?     ; true if an agent is evacuated, either in a shelter or outside of the shelter
  dead?          ; true if an agent is dead and caught by the tsunami
  free_speed     ; max speed a cui può andare il pedone
  speed          ; speed of the agent, measured in patches per tick
  path           ; list of intersection 'who's that represent the path to the shelter of an agent
  decision       ; the agents decision code: 1 for Hor Evac on foot
                 ;                           3 for Ver Evac on foot
  time_in_water  ; time that the agent has been in the water in seconds
  density_ahead  ; the density ahead of the agent in the current intersection
  side           ; either the left or right sidewalk of the road {Left = 0, Right = 1}
  crossing?
  crossing_int
  moved?
  prev_int
  arrival_time
]

cars-own [       ; the variables that cars own
  id             ; resident id
  current_int    ; current/previous intersection of an agent, 0 if none
  moving?        ; true if the agent is moving, false if not (e.g., turning at intersection)
  evacuated?     ; true if an agent is evacuated, either in a shelter or outside of the shelter
  dead?          ; true if an agent is dead and caught by the tsunami
  next_int       ; the next intersection an agent is heading towards
  shelter        ; 'who' of the intersection that the agent is heading to (its shelter)
  speed          ; speed of the agent, measured in patches per tick
  path           ; list of intersection 'who's that represent the path to the shelter of an agent
  decision       ; the agents decision code: 2 for Hor Evac by Car
                 ;                           4 for Ver Evac by Car
  car_ahead      ; the car that is immediately ahead of the agent
  space_hw       ; the space headway between the agent and 'car_ahead'
  speed_diff     ; the speed difference between the agent and 'car_ahead'
  acc            ; acceleration of the car agent
  road_on        ; the link that the car is travelling on
  time_in_water  ; time that the agent has been in the water in seconds
  density_ahead  ; the density ahead of the agent in the current intersection
  crossing?      ;
  prev_int       ; previous intersection of an agent in a crossroad
  moved?

  waiting?       ; waiting for pedestrian crossing
  rightofway?
  arrival_time
]

globals [        ; global variables
  ev_times       ; list of evacuation times (in mins) for all agents referenced from the earthquake
                 ; later to be used to look into the distribution of the evacuation times
  mouse-was-down?; event-handler variable to capture mouse clicks accurately
  road_network   ; contains the road network gis information
  population_distribution
  ; contains population distribution gis information
  shelter_locations
  ; contains shelter locations gis information

  tsunami_sample ; sample tsunami inundation wavefiled raster data

  tsunami_data_inc   ; the increements in seconds for the inundation data
  tsunami_data_start ; the start of the inundation data in seconds
  tsunami_data_count ; count of inunudaiton files

  tsunami_max_depth    ; maximum observed depth for color normalization
  tsunami_min_depth    ; minimum observed depth for color normalization


  mortality_rate ; mortality rate of the event

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;;;;;;;;; CONVERSION RATIOS ;;;;;;;;;
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  patch_to_meter ; patch to meter conversion ratio
  patch_to_feet  ; patch to feet conversion ratio
  fd_to_ftps     ; fd (patch/tick) to feet per second
  fd_to_mph      ; fd (patch/tick) to miles per hour
  fd_to_kmh      ; fd (patch/tick) to kilometers per hour
  tick_to_sec    ; ticks to seconds - usually 1

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;;;;;;;;;; TRANSFORMATIONS ;;;;;;;;;;
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  min_lon        ; minimum longitude that is associated with min_xcor
  min_lat        ; minimum latitude that is associated with min_ycor

  origin_straight
  origin_left
  origin_left_straight

  side_width
  lane_width
  int_width

  road_data
  intersection_data
  intersection_times

  ;; global agentsets
  crossroads
  int-roads

  evacuee_times
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;; HELPER FUNCTIONS ;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; returns truen if the moouse was clicked
to-report mouse-clicked?
  report (mouse-was-down? = true and not mouse-down?)
end

; returns a list of intersections for which the shortest path to the closest shelter should be calculated
to-report find-origins
  let origins []
  ask residents [
    ; add the closest intersection to each agent at the start of the simulation to the origins
    ; there is no need to calculate the shortest path for the rest of the intersections
    set origins lput min-one-of intersections [ distance myself ] origins
  ]
  set origins remove-duplicates origins
  report origins
end

; generates a randomly drawn number from Rayleigh dist. with the given sigma
to-report rayleigh-random [sigma]
  report (sqrt((- ln(1 - random-float 1 ))*(2 *(sigma ^ 2))))
end

; TURTLE FUNCTION: sets random decision as to the mode (foot/car) and the shelter (horizontal/vertical) for the evaucation based on the percentages entered by the user
;                  in addition, it sets the appropriate milling time based on the decision and its corresponding Rayleigh dist. parameters entered by the user
to make-decision
  let rnd random-float 100
  ifelse (rnd < R1_HorEvac_Foot ) [
    set decision 1
    set miltime ((Rayleigh-random Rsig1) + Rtau1 ) * 60 / tick_to_sec
  ]
  [
    ifelse (rnd >= R1_HorEvac_Foot and rnd < R1_HorEvac_Foot + R2_HorEvac_Car ) [
      set decision 2
      set miltime ((Rayleigh-random Rsig2) + Rtau2 ) * 60 / tick_to_sec
    ]
    [
      ifelse (rnd >= R1_HorEvac_Foot + R2_HorEvac_Car and rnd < R1_HorEvac_Foot + R2_HorEvac_Car + R3_VerEvac_Foot ) [
        set decision 3
        set miltime ((Rayleigh-random Rsig3) + Rtau3 ) * 60 / tick_to_sec
      ]
      [
        if (rnd >= R1_HorEvac_Foot + R2_HorEvac_Car + R3_VerEvac_Foot and rnd < R1_HorEvac_Foot + R2_HorEvac_Car + R3_VerEvac_Foot + R4_VerEvac_Car ) [
          set decision 4
          set miltime ((Rayleigh-random Rsig4) + Rtau4 ) * 60 / tick_to_sec
        ]
      ]
    ]
  ]
end


; finds the shortest path from and intersection (source) to a shelter (one of gls) with A* algorithm
; gl is only used as a heuristic for the algorithm, the closest destination in a network is not necessarily the closest in euclidean distance
to-report Astar [ source gl gls]
  let rchd? false       ; true if the algorithm has found a shelter
  let dstn nobody       ; the destinaton or the closest shelter
  let closedset []      ; equivalent to closed set in A* alg
  let openset []        ; equivalent to open set in A* alg
  ask intersections [   ; initialize "previous", which later will be used to reconstruct the shortest path for each intersection
    set previous -1
  ]
  set openset lput [who] of source openset  ; start the open set with the source intersection
  ask source [                              ; initialize g and f score for the source intersection
    set gscore 0
    set fscore (gscore + distance gl)
  ]
  while [ not empty? openset and (not rchd?)] [ ; while a destination hasn't been found, look for one
    let current Astar-smallest openset          ; pick the most promissing intersection from the open set
    if member? current  [who] of gls [          ; if it is one of the candid shelters, we're done
      set dstn intersection current             ; set the destination
      set rchd? true                            ; and toggle the flag so we don't look for a destination anymore and move on to the recosntructing the path
    ]
    set openset remove current openset          ; update the open and closed set
    set closedset lput current closedset
    ask intersection current [                  ; explore the neighbors of the current intersection
      ask out-road-neighbors [
        let tent_gscore [gscore] of myself + [link-length] of (road [who] of myself who) ; update f and gscore tentatively
        let tent_fscore tent_gscore + distance gl
        if ( member? who closedset and ( tent_fscore >= fscore ) ) [stop]                  ; if not improved, stop
        if ( not member? who closedset or ( tent_fscore >= fscore )) [                     ; if the score improved, continue updating
          set previous current
          set gscore tent_gscore
          set fscore tent_fscore
          if not member? who openset [
            set openset lput who openset
          ]
        ]
      ]
    ]
  ]
  let route []                                    ; reconstruct the path to destination
  ifelse dstn != nobody [                         ; if there was a path
    while [ [previous] of dstn != -1 ] [          ; use "previous" to recosntruct untill "previous" is -1
      set route fput [who] of dstn route
      set dstn intersection ([previous] of dstn)
    ]
  ]
  [
    set route []                                  ; if there was no path, return an empty list
  ]
  report route
end

; returns the who of an intersection in who_list with the lowest fscore
to-report Astar-smallest [ who_list ]
  let min_who 0
  let min_fscr 100000000
  foreach who_list [ [?1] ->
    let fscr [fscore] of intersection ?1
    if fscr < min_fscr [
      set min_fscr fscr
      set min_who ?1
    ]
  ]
  report min_who
end

; TURTLE FUNCTION: calculates the speed of the car based on general motors car-following model
;                  it incorporates the speed of the leading car as well as the space headway
to move-gm
  set car_ahead cars in-cone (150 / patch_to_feet) 20                    ; get the cars ahead in 150ft (almost half a block) and in field of view of 20 degrees
  set car_ahead car_ahead with [
    self != myself and                                                   ; that are not myself
    moving? and                                                          ; that are moving
    not evacuated? and                                                   ; that have not made it to the shelter yet (no congestion at the shelter)
    not dead? and                                                        ; that have not died yet
    current_int = [current_int] of myself and                            ; on the same road
    next_int = [next_int] of myself and
    abs(subtract-headings heading [heading] of myself) < 160 and         ; with relatively the same general heading as mine (not going the opposite direction)
    distance myself > 0.0001                                             ; not exteremely close to myself
  ]

  set car_ahead min-one-of car_ahead [distance myself]                                       ; and the closest car ahead

  ifelse is-turtle? car_ahead [                                                              ; if there IS a car ahead:
    set space_hw distance car_ahead                                                          ; the space headway with the leading car
    set speed_diff [speed] of car_ahead - speed                                              ; the speed difference with the leadning car
    ifelse space_hw < (6 / patch_to_feet) [set speed 0]                                      ; if the leading car is less than ~6ft away, stop
    [                                                                                        ; otherwise, find the acceleration based on the general motors car-following model
      set acc (alpha / fd_to_mph * 5280 / patch_to_feet) * ((speed) ^ 0) / ((space_hw) ^ 2) * speed_diff
      ; converting mi2/hr to patch2/tick = converting mph*mi to fd*patch
      ; m = speed componnent = 0 / l = space headway component = 2
      set speed speed + acc                                                                  ; update the speed
    ]
    if speed > (space_hw - (6 / patch_to_feet)) [                                            ; if the current speed will put the car less than 6ft away from the leading car in the next second,
      set speed min list (space_hw - (6 / patch_to_feet)) [speed] of car_ahead               ; reduce the speed in a way to not get closer to the leading car
    ]
    if speed > (max_speed / fd_to_mph) [set speed (max_speed / fd_to_mph)]                   ; cap the speed to max speed if larger
    if speed < 0 [set speed 0]                                                               ; no negative speed
  ]
  [                                                                                          ; if ther IS NOT a car ahead:
    if speed < (max_speed / fd_to_mph) [set speed speed + (acceleration / fd_to_ftps * tick_to_sec)]
    ; accelerate to get to the speed limit
    if speed > max_speed / fd_to_mph [set speed max_speed / fd_to_mph]                       ; cap the speed to max speed if larger
  ]

  if speed > distance next_int [set speed distance next_int]                                 ; avoid jumping over the next intersection the car is heading to
end


;; definition of the density a head of a pedestrian considering roads with two sidewalk and two-way flow on each.
to update-density-ahead-pedestrians

  ;; select the patch in-front of myself
  let phi 180
  let search_length 9.84252 ;;13.1234 = 4 meters, 9.84252 = 3 meters

  ;; select the patch ahead of myself
  ;; if the search lenght is over the next intersection the search length is reduced to the distance to the next intersection
  if search_length / patch_to_feet > distance next_int  [
    set search_length distance next_int * patch_to_feet
  ]

  let peds_ahead pedestrians in-cone (search_length / patch_to_feet) phi                       ; get the pedestrians ahead in search_length (almost half a block) and in field of view of phi degrees

  set peds_ahead peds_ahead with [
    self != myself and                                             ; that are not myself
    not evacuated? and                                             ; that have not made it to the shelter yet (no congestion at the shelter)
    not dead? and                                                  ; that have not died yet
    side = [side] of myself                                        ; that have are on the same side of the sidewalk
  ]

  ifelse count peds_ahead != 0 [
    ;; search_length from ft to m
    let m_search_length search_length / 3.281

    ;; side_width from ft to m
    let m_side_width side_width / 3.281

    ;; lane_width from ft to m
    let m_lane_width lane_width / 3.281

    let p_area_ahead (m_side_width * m_search_length)

    ;; if the evacuation does not include cars, pedestrians occupy the whole street
    if R2_HorEvac_Car = 0 and R4_VerEvac_Car = 0 [
      set p_area_ahead (m_side_width * 2  + m_lane_width * 2) * m_search_length
    ]

    set density_ahead (count peds_ahead) / p_area_ahead ; ped/m²
  ][
    set density_ahead 0
  ]
end


to-report update-pedestrian-speed [fs d]
  let s fs

  if d != 0 [
    ifelse (d >= jam_density) [
      set s 0
    ][
      let k gamma * ((1 / d) - (1 / jam_density))
      set s fs * (1 - e ^ (- k))
    ]
  ]

  report min list fs s
end


to-report get-sorted-intersections [prev curr]
  let in_dir [link-heading] of road ([who] of prev) ([who] of curr)
  set in_dir (in_dir - 180) mod 360

  let curr_int current_int
  let directions []

  ask curr [
    ;; TODO: can be optimized
    ask out-link-neighbors with [self != prev] [
      let angle [link-heading] of road ([who] of myself) ([who] of self)
      set angle (angle - in_dir) mod 360 ; substract the initial angle
      set directions lput (list ([who] of self) angle) directions

    ]
    ask in-link-neighbors with [self != prev] [
      let angle [link-heading] of road ([who] of self) ([who] of myself)
      set angle ((angle - 180) mod 360 - in_dir) mod 360 ; substract the initial angle

      set directions lput (list ([who] of self) angle) directions
    ]
  ]

  set directions sort-by [[a b] -> (item 1 a) < (item 1 b)] directions ; sort by decreasing angle
  set directions map [ x -> item 0 x ] directions                      ; get sorted intersections
  set directions remove-duplicates directions

  report directions
end

to-report get-next-direction [prev curr next]
  let directions get-sorted-intersections prev curr

  let idx position [who] of next directions                            ; get index of the destination

  (ifelse
    length directions = 3 [
      report item idx ["left" "straight" "right"]
    ]
    length directions = 2 [
      report item idx ["left" "right"]
    ]
    [
      error "the crossroad has not three or four out roads"
    ]
  )
end


to-report map-direction-intersection [prev curr next]
  let dir-int table:make

  let ints get-sorted-intersections prev curr
  set ints lput ([who] of prev) ints

  let dirs []

  if length ints = 4 [
    set dirs ["left" "straight" "right" "origin"]
  ]
  if length ints = 3 [
    set dirs ["left" "right" "origin"]
  ]

  (foreach dirs ints [[x y] -> table:put dir-int x y])

  report dir-int
end

; TURTLE FUNCTION: marks an agent as evacuee
to mark-evacuated
  if not evacuated? and not dead? [                              ; if the agents is not dead or evacuated, mark it as evacuated and set proper characteristics
    set color green
    set moving? false
    set evacuated? true
    set dead? false
    set ev_times lput ( ticks * tick_to_sec / 60 ) ev_times      ; add the evacuees evacuation time (in minutes) to ev_times list
    ask current_int [set evacuee_count evacuee_count + 1]        ; increment the evacuee_count of the shelter the agent evacuated to
  ]
end

; TURTLE FUNCTION: marks an agent as dead
to mark-dead                                                     ; mark the agent dead and set proper characteristics
  set color red
  set moving? false
  set evacuated? false
  set dead? true
  set-casualties
end

; returns true if the general direction (north, east, south, west) and the heading (0 <= h < 360) are alligned
; used for removing one-way roads
to-report is-heading-right? [link_heading direction]
  if direction = "north" [ if abs(subtract-headings 0 link_heading) <= 90 [report true]]
  if direction = "east" [ if abs(subtract-headings 90 link_heading) <= 90 [report true]]
  if direction = "south" [ if abs(subtract-headings 180 link_heading) <= 90 [report true]]
  if direction = "west" [ if abs(subtract-headings 270 link_heading) <= 90 [report true]]
  report false
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; SETUP INITIAL PARAMETERS ;:;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; this function sets some initial value for an initial try to run the model
; if the user decides not to tweak any of the inputs
to setup-init-val
  set immediate_evacuation False  ; agents do not start evacuation immediately, instead they follow a Rayleigh distribution for their milling time
  set R1_HorEvac_Foot 50          ; 25% of the agents evacuate horizontally on foot
  set R2_HorEvac_Car 50           ; 25% of the agents evacuate horizontally with their car
  set R3_VerEvac_Foot 0           ; 25% of the agents evacuate on foot and are open to vertical evaucation if it is closer to them compared to a shelter outside the inundation zone
  set R4_VerEvac_Car 0            ; 25% of the agents evacuate with their car and are open to vertical evaucation if it is closer to them compared to a shelter outside the inundation zone
  set Hc 1.0                      ; the critical wave height that marks the threshold of casualties is set to 1.0 meter
  set Tc 120                      ; the time it takes for the inundation above Hc to kill an agent (seconds)
  set max_speed 35                ; maximum driving speed is set to 35 mph
  set acceleration 5              ; acceleration of the vehicles is set to 5 ft/s2
  set deceleration 25             ; deceleration of the vehicles is set to 25 ft/s2
  set alpha 0.14                  ; alpha parameter of the car-following model is set to 0.14 mi2/hr (free-flow speed = 35 mph & jam density = 250 veh/mi/lane)
  set Rtau1 10                    ; minimum milling time for all decision categories is set to 10 minutes
  set Rtau2 10
  set Rtau3 10
  set Rtau4 10
  set Rsig1 1.65                  ; the scale factor parameter of the Rayleigh distribution for all decision categories is set to 1.65
  set Rsig2 1.65                  ; meaning that 99% of the agents evacuate within 5 minutes after the minimum milling time (between 10 to 15 mins in this case)
  set Rsig3 1.65
  set Rsig4 1.65
  set gamma 1.913
  set jam_density 5.4; p/m²
  set free_flow_speed 1.34; m/s
  set iteration 1
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;; READ GIS FILES ;:;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; read the gis files that are used to populate the model:
;   1. road_network that contains the transportation network data
;   2. shelter_locations that contains the location of the horizontal and vertical shelters
;   3. population_distribution that contains the coordinates of the agents immediately before the evacuation
to read-gis-files
  gis:load-coordinate-system "road_network/road_network.prj"                                          ; load the projection system - WGS84 / UTM (METER) for your specific area
  set shelter_locations gis:load-dataset "shelter_locations/shelter_locations.shp"                    ; read shelter locations
  set road_network gis:load-dataset "road_network/road_network.shp"                                   ; read road network
  set population_distribution gis:load-dataset "population_distribution/population_distribution.shp"  ; read population distribution
  set tsunami_sample gis:load-dataset "tsunami_inundation/sample.asc"                                 ; just a sample inunudation wavefield to get the envelope (TODO: can be fixed later)
  let world_envelope (gis:envelope-union-of (gis:envelope-of road_network)                                ; set the real world bounding box the union of all the read shapefiles
    (gis:envelope-of shelter_locations)
    (gis:envelope-of population_distribution)
    (gis:envelope-of tsunami_sample))
  let netlogo_envelope (list (min-pxcor + 1) (max-pxcor - 1) (min-pycor + 1) (max-pycor - 1))             ; read the size of netlogo world
  gis:set-transformation (world_envelope) (netlogo_envelope)                                              ; make the transformation from real world to netlogo world
  let world_width item 1 world_envelope - item 0 world_envelope                                           ; real world width in meters
  let world_height item 3 world_envelope - item 2 world_envelope                                          ; real world height in meters
  let world_ratio world_height / world_width                                                              ; real world height to width ratio
  let netlogo_width (max-pxcor - 1) - ((min-pxcor + 1))                                                   ; netlogo width in patches (minus 1 patch padding from each side)
  let netlogo_height (max-pycor - 1) - ((min-pycor + 1))                                                  ; netlogo height in patches (minus 1 patch padding from each side)
  let netlogo_ratio netlogo_height / netlogo_width                                                        ; netlogo height to width ratio
                                                                                                          ; calculating the conversion ratios
  set patch_to_meter max (list (world_width / netlogo_width) (world_height / netlogo_height))             ; patch_to_meter conversion multiplier
  set patch_to_feet patch_to_meter * 3.281     ; 1 m = 3.281 ft                                           ; patch_to_feet conversion multiplier
  set tick_to_sec 1.0                                                                                     ; tick_to_sec ratio is set to 1.0 (preferred)
  set fd_to_ftps patch_to_feet / tick_to_sec                                                              ; patch/tick to ft/s speed conversion multipler
  set fd_to_mph fd_to_ftps * 0.682            ; 1ft/s = 0.682 mph                                        ; patch/tick to mph speed conversion multiplier
  set fd_to_kmh fd_to_ftps * 1.097                                                                       ; patch/tick to kmh speed conversion multiplier
                                                                                                         ; to calculate the minimum longitude and latitude of the world associated with min_xcor and min_ycor
                                                                                                         ; we need to check and see how the world envelope fits into that of netlogo's. This is why the "_ratio"s need to be compared againsts eachother
                                                                                                         ; this is basically the missing "get-transformation" premitive in netlogo's GIS extension
  ifelse world_ratio < netlogo_ratio [
    set min_lon item 0 world_envelope - patch_to_meter
    set min_lat item 2 world_envelope - ((netlogo_ratio - world_ratio) / netlogo_ratio / 2) * netlogo_height * patch_to_meter - patch_to_meter
  ][
    set min_lon item 0 world_envelope - ((world_ratio - netlogo_ratio) / world_ratio / 2) * netlogo_width * patch_to_meter - patch_to_meter
    set min_lat item 2 world_envelope - patch_to_meter
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;; LOAD NETWORK ;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; loads the transportation network, consisting of roads and intersections from "road_network" gis files
; that are places under "road_network" directroy. Note the "direction" attribute associated with each road
; which can either be "two-way" "north" "east" "south" or "west".
to load-network
  ; first remove the intersections and roads, if any
  ask intersections [die]
  ask roads [die]
  ; start loading the network
  foreach gis:feature-list-of road_network [ i ->                                      ; iterating through features to create intersections and roads
    let direction gis:property-value i "DIRECTION"                                     ; get the direction of the link to make either a one- or two-way road
    foreach gis:vertex-lists-of i [ j ->                                               ; iterating through the list of vertex lists (usually lengths of 1) of each feature
      let prev -1                                                                      ; previous vertex indicator, -1 if None
      foreach j [ k ->                                                                 ; iterating through the vertexes
        if length ( gis:location-of k ) = 2 [                                          ; check if the vertex is valid with both x and y values
          let x item 0 gis:location-of k                                               ; get x and y values for the intersection
          let y item 1 gis:location-of k
          let curr 0

          let ints intersections with [xcor = x and ycor = y]
          ifelse any? ints [                                                           ; check if there is an intersection here, if not, make one, and if it is, use it
            set curr [who] of one-of ints
          ][
            create-intersections 1 [
              set xcor x
              set ycor y
              set shelter? false
              set size 0.1
              set shape "square"
              set color white
              set curr who
              set evacuee_list []
            ]
          ]
          if prev != -1 and prev != curr [                                             ; if this intersection is not the starting intersection, make roads
            ifelse direction = "two-way" [                                             ; if the road is "two-way" make both directions
              ask intersection prev [create-road-to intersection curr]
              ask intersection curr [create-road-to intersection prev]
            ][                                                                         ; if not, make only the direction that matches the direction requested, see is-heading-right? helper function
              if is-heading-right? ([towards intersection curr] of intersection prev) direction [ ask intersection prev [create-road-to intersection curr]]
              if is-heading-right? ([towards intersection prev] of intersection curr) direction [ ask intersection curr [create-road-to intersection prev]]
            ]
          ]
          set prev curr
        ]
      ]
    ]
  ]

  ; remove too close intersections
  ask intersection 432 [ die ]
  ask intersection 396 [
    create-road-to intersection 433
    create-road-to intersection 59
  ]
  ask intersection 59 [
    create-road-to intersection 396
  ]


  ; assign crossroad? and crossing_counts variables
  ; init also arrival-queue
  ask intersections [
    set crossroad? length remove-duplicates [who] of link-neighbors = 4 ; > 2
    set crossing_counts table:make
    set arrival-queue []
    set crossing-cars []
    set stops []
    set car-delay []
  ]

  ; mark two-way stops
  let two-ways csv:from-file "road_network/two-way.csv"
  foreach two-ways [i ->
    let int_who item 0 i
    let stops_who sublist i 1 length i

    ask intersection int_who [
      if crossroad? [
        set stops map [x -> intersection x] stops_who
      ]
    ]
  ]

  ; assign mid-x and mid-y variables to the roads that respresent the middle point of the link
  ask roads [
    set color black
    set thickness 0.05
    set mid-x mean [xcor] of both-ends
    set mid-y mean [ycor] of both-ends
    set traffic 0
    set crowd 0
    set shape "road"

    set car-in-h []
    set car-out-h []
    set car-in-t 0
    set car-out-t 0

    set ped-flow []
    set casualties 0
  ]

  output-print "Network Loaded"
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;; LOAD SHELTERS ;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; loads the shelters from from "shelter_locations" gis files that are under "shelter_locations" directory
; note the "type" attribute associated with each shelter in the gis file, which can either be "hor" or "ver"
; for horizontal and vertical shelters.
to load-shelters
  ; remove all the shelters before loading them
  ask intersections [
    set shelter? false
    set shelter_type "None"
    set color white
    set size 0.1
  ]
  ; start loading the shelters
  foreach gis:feature-list-of shelter_locations [ i ->     ; iterate through the shelters
    let curr_shelter_type gis:property-value i "TYPE"      ; get the type of the shelter
    foreach gis:vertex-lists-of i [ j ->
      foreach j [ k ->
        if length ( gis:location-of k ) = 2 [              ; check if the vertex has both x and y
          let x item 0 gis:location-of k
          let y item 1 gis:location-of k
          ask min-one-of intersections [distancexy x y][   ; turn the closest intersection to (x,y) to a shelter
            set shelter? true
            set crossroad? false
            set shape "circle"
            set size 4
            if curr_shelter_type = "hor" [                 ; assign proper type based on "curr_shelter_type"
              set shelter_type "Hor"
              set color yellow
            ]
            if curr_shelter_type = "ver" [
              set shelter_type "Ver"
              set color violet
            ]
            st
          ]
        ]
      ]
    ]
  ]
  output-print "Shelters Loaded"
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;; LOAD TSUNAMI DATA ;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; loads the tsunami inundation data from the flowdepth raster files under "tsunami_inundation" directory
; the details of inundation data (e.g., the increment, start, and data count) are read from "details.txt"
; if no tsunami data is provided, this function writes the coordinate boundaries of the study area into
; "coordinate_boundaries.txt" so it can be used to create the flowdepths later on.

to load-tsunami
  ask patches [set depths []]
  file-close-all
  ifelse file-exists? "tsunami_inundation/details.txt" [
    file-open "tsunami_inundation/details.txt"
    set tsunami_data_start file-read
    set tsunami_data_inc file-read
    set tsunami_data_count file-read
    file-close
    let files n-values tsunami_data_count [i -> i * tsunami_data_inc + tsunami_data_start ]
    set tsunami_max_depth 0
    set tsunami_min_depth 9999
    foreach files [? ->
      ifelse file-exists? (word "tsunami_inundation/" ? ".asc") [
        let tsunami gis:load-dataset (word "tsunami_inundation/" ? ".asc")
        gis:apply-raster tsunami depth
        ask patches [
          if not ((depth <= 0) or (depth >= 0)) [   ; If NaN
            set depth 0
          ]
          if depth > tsunami_max_depth [set tsunami_max_depth depth]
          if depth < tsunami_min_depth [set tsunami_min_depth depth]
          set depths lput depth depths
        ]
      ]
      [
        output-print (word "File tsunami_inundation/" ? ".asc is missing!")
      ]
      ask patches [set depth 0]
    ]
    output-print "Tsunami Data Loaded"
  ]
  [
    ; if the tsunami data is not provided, save coordinate boundaires to "coordinate_boundaries.text"
    let file_name "tsunami_inundation/boundaries.txt"
    if file-exists? file_name [file-delete file_name]         ; if there already is a file, delete it and make a new one
    file-open file_name
    file-print "top left (lon,lat)"
    file-print (word min_lon "," (min_lat + (world-height * patch_to_meter)))
    file-print "bottom right (lon,lat)"
    file-print (word (min_lon + (world-width * patch_to_meter)) "," min_lat)
    file-close
    output-print "Bounrdaries coordinates are saved to tsunami_inundation/boundaries.txt"
  ]
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;; BREAK LINKS ;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; removes both directions of a link with a mouse click to the mid point of the link
to break-links
  let mouse-is-down? mouse-down?
  if mouse-clicked? and timer > 0.1 [
    reset-timer
    let lnk min-one-of roads [(mouse-xcor - mid-x) ^ 2 + (mouse-ycor - mid-y) ^ 2]
    let ints sort [both-ends] of lnk
    if is-link? road [who] of item 0 ints [who] of item 1 ints [
      ask road [who] of item 0 ints [who] of item 1 ints [die]
    ]
    if is-link? road [who] of item 1 ints [who] of item 0 ints [
      ask road [who] of item 1 ints [who] of item 0 ints [die]
    ]
    display
  ]
  set mouse-was-down? mouse-is-down?
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; PICK VERTICAL SHELTERS ;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; turns an intersection into a vertical evacuation shelter with a mouse click
to pick-verticals
  let mouse-is-down? mouse-down?
  if mouse-clicked? [
    ask min-one-of intersections [distancexy mouse-xcor mouse-ycor][
      set shelter? true
      set shelter_type "Ver"
      set shape "circle"
      set size 4
      set color violet
    ]
    display
  ]
  set mouse-was-down? mouse-is-down?
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;; LOAD POPULATION ;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; loads the evacuees from "population_distribution" gis files that are located under "population_distribution" directroy
; this gis shapefile contains the coordinates of the evacuees at the start of the evacuation
to load-population
  ; remove any residents, cars, or pedestrians before loading the population
  ask residents [ die ]
  ask pedestrians [die]
  ask cars [die]
  ; start loading the population
  foreach gis:feature-list-of population_distribution [ i ->           ; iterate through the points in the features
    foreach gis:vertex-lists-of i [ j ->
      foreach j [ k ->
        if length ( gis:location-of k ) = 2 [                          ; check if the vertex has both x and y
          let x item 0 gis:location-of k
          let y item 1 gis:location-of k
          create-residents 1 [                                         ; create the agent
            set xcor x
            set ycor y
            set color brown
            set shape "dot"
            set size 2
            set moving? false                                          ; they agents are staionary at the beginning, before they start the evacuation
            set init_dest min-one-of intersections [ distance myself ] ; the first intersection an agent moves toward to
                                                                       ; to get to the transpotation network

            set speed free_flow_speed
            ;            set speed random-normal 1.34 0.37
            ;            set speed min list speed 1.66
            ;            set speed max list speed 0.75
            set speed speed / patch_to_meter                               ; turning ft/s to patch/tick

            if speed < 0.001 [set speed 0.001]                         ; if speed is too low, set it to very small non-zero value
            set evacuated? false                                       ; initialized as not evacuated
            set dead? false                                            ; initialized as not dead
            set reached? false                                         ; initialized as not reached the transportation network
            make-decision                                              ; sets the evacuation mode and shelter decision and the corresponding milling time
            if immediate_evacuation [                                  ; if immediate_evacuation is toggled on, set all the milling times to 0
              set miltime 0
            ]
          ]
        ]
      ]
    ]
  ]
  output-print "Population Loaded"
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;; LOAD ROUTES ;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; calcualtes routes for the intersections that need the shortest path information to a shelter, not all the intersections
to load-routes
  let origins find-origins
  ask turtles with [member? self origins] [
    let goals intersections with [shelter? and shelter_type = "Hor"]
    set hor-path Astar self (min-one-of goals [distance myself]) goals ; hor-path definitely goes to a horizontal shelter
    set goals intersections with [shelter?]
    set ver-path Astar self (min-one-of goals [distance myself]) goals ; ver-path can go to either a vertical shelter or
                                                                       ; a horizontal shelter, depending on which one was closer
  ]
  output-print "Routes Calculated"
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;; LOAD 1/2 ;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; first part of loading the model, including transportation network, shelters, and tsunami data
; before breaking roads and adding vertical shelters
to load1
  ca

  print (word "Foot %: " R1_HorEvac_Foot  " - Miltime min: " Rtau1)
  ask patches [set pcolor white]

  set ev_times []
  set evacuee_times table:make

  set road_data []
  set road_data lput (list "end1" "end2" "traffic" "crowd" "minute" "mean speed car" "mean speed ped" "casualties") road_data
  set intersection_data []
  set intersection_data lput (list "who" "car-delay" "car-in-flow" "car-out-flow" "p-in-flow" "p-out-flow" "minute") intersection_data
  set intersection_times []
  set intersection_times lput (list "who" "mean car evacuation time" "mean ped evacuation time") intersection_times

  set side_width 5 ; feet
  set lane_width 12 ; feet
  set int_width (side_width + lane_width) * 2

  read-gis-files
  load-network
  load-shelters
  load-tsunami

  set crossroads intersections with [crossroad?]
  set int-roads roads with [[crossroad?] of end1 or [crossroad?] of end2]

  reset-timer
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;; LOAD 2/2 ;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; second part of loading the model, including population distribution and the routes
; after breaking the roads and adding the vertical shelters
; calculating roads is based on the vertical shelters and current state of the roads
to load2
  load-population
  load-routes
  init-right-of-way-rules
  reset-ticks
end

;######################################
;*************************************#
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;*#
;;;;;;;;;;;;;    GO    ;;;;;;;;;;;;;;*#
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;*#
;*************************************#
;######################################
to go
  if int(((ticks * tick_to_sec) - tsunami_data_start) / tsunami_data_inc) = tsunami_data_count - 1 [
    stop ; stop after simulation all the flow depths
  ]

  ; update the tsunami depth every interval seconds
  if int(ticks * tick_to_sec) - tsunami_data_start >= 0 and
  (int(ticks * tick_to_sec) - tsunami_data_start) mod tsunami_data_inc = 0 [
    if int(((ticks * tick_to_sec) - tsunami_data_start) / tsunami_data_inc) < tsunami_data_count [
      ask patches with [depths != 0][
        set depth item int(((ticks * tick_to_sec) - tsunami_data_start) / tsunami_data_inc) depths   ; set the depth to the correct item of depths list (depending on the time)
        if depth > max_depth [                                                                       ; monitor the maximum depth observed at each patch, for future use.
          set max_depth depth
        ]
      ]
    ]    ; recolor the patches based on the tsunami depth, the deeper the darker the shade of blue
    set tsunami_min_depth 0 ; TODO: Find a better scaling scheme - With this line, white maps to 0 m and balck to tsunami_max_depth
    ask patches [
      set pcolor scale-color blue depth tsunami_max_depth tsunami_min_depth
    ]
  ]

  residents-behaviour

  pedestrians-behaviour

  cars-behaviour

  ; cars coordination in interections
  handle-crossing-cars

  ; mark agents who were in the water for a prolonged period of time dead
  ask residents with [time_in_water > Tc and not dead?][mark-dead]
  ask cars with [time_in_water > Tc and not dead?][mark-dead]
  ask pedestrians with [time_in_water > Tc and not dead?][mark-dead]

  ; update mortality rate
  set mortality_rate count turtles with [color = red] / (count residents + count pedestrians + count cars) * 100

  tick
end



to init-right-of-way-rules
  set origin_left (list
    (list "left" "right")
    (list "right" "left")
    (list "right" "right")
    (list "straight" "right")
  )

  set origin_straight (list
    (list "left" "left")
    (list "right" "right")
    (list "right" "straight")
    (list "straight" "right")
    (list "straight" "straight")
  )

  set origin_left_straight (list
    (list "right" "left" "right")
    (list "left" "right" "left")
    (list "right" "right" "right")
    (list "straight" "right" "right")
  )
end


to-report find-right-of-way
  let len length arrival-queue
  let available-cars []
  let car-dir table:from-list (list (list "origin" nobody) (list "left" nobody) (list "right" nobody) (list "straight" nobody))

  if len > 0 [
    set available-cars (turtle-set arrival-queue) with-min [arrival_time]
    set available-cars sort-on [distance next_int] available-cars

    let first-car item 0 available-cars

    if [not moved?] of first-car [

      ;; if only one car is present return immediately
      if length available-cars = 1 [
        table:put car-dir "origin" first-car
        report car-dir
      ]

      set available-cars turtle-set available-cars

      ; keep only the first one that comes from each intersection
      ask first-car [
        if not empty? path [
          let int-dir map-direction-intersection current_int next_int (intersection item 0 path)
          table:remove int-dir "origin"

          foreach table:to-list int-dir [x ->
            let key item 0 x
            let val item 1 x

            let next-car min-one-of (available-cars with [current_int = intersection val]) [distance next_int]
            table:put car-dir key next-car
          ]
        ]
      ]

      table:put car-dir "origin" first-car

      ; set right-of-way order
      let r_car table:get car-dir "right"
      let l_car table:get car-dir "left"
      let s_car table:get car-dir "straight"

      if r_car != 0 [
        ifelse s_car = 0 and l_car = 0 [
          set car-dir table:from-list (list (list "origin" r_car) (list "left" first-car) (list "straight" 0) (list "right" 0))
        ][
          if s_car = 0 [
            set car-dir table:from-list (list (list "origin" r_car) (list "left" first-car) (list "straight" l_car) (list "right" 0))
          ]
          if l_car = 0 [
            set car-dir table:from-list (list (list "origin" s_car) (list "left" 0) (list "straight" first-car) (list "right" l_car))
          ]
        ]
      ]
    ]
  ]

  report car-dir
end


to residents-behaviour
  ask residents [
    ; ask residents, if they milling time has passed, to start moving
    if not moving? and not dead? and miltime <= ticks [
      set heading towards init_dest
      set moving? true
    ]

    ; ask residents that should be moving to move
    if moving? [
      ifelse (distance init_dest < (speed) ) [fd distance init_dest][fd speed]
      if distance init_dest < 0.005 [   ; if close enough to the next intersection, move the agent to it
        move-to init_dest
        set moving? false
        set reached? true
        set current_int init_dest
      ]
    ]

    ifelse reached? [
      ; ask residets who have reached the network to hatch into a pedestrian or a car depending on their decision
      let spd speed                ; to pass on the spd from resident to the hatched pedestrian
      let dcsn decision            ; to pass on the decision from the resident to either car or pedestrian
      let resident_id who

      if dcsn = 1 or dcsn = 3 [    ; horizontal (1) or vertical (3) evacuation - by FOOT
        ask current_int [          ; ask the current intersection of the resident to hatch a pedestrian
          let in_nodes in-link-neighbors

          let _who 0
          hatch-pedestrians 1 [
            set _who who
            set id resident_id
            set size 0.5 ; 2
            set shape "dot"
            set current_int myself ; myself = current_int of the resident
            set free_speed spd     ; the speed of the resident is passed on to the pedestrian as free_speed
            set speed free_speed   ; the actual speed of the pedestrian is set to the free_speed
            set evacuated? false   ; initialized as not evacuated, will be checked immediately after being born
            set dead? false        ; initialized as not dead, will be checked immediately after being born
            set moving? false      ; initialized as not moving, will start moving immediately after if not evacuated and not dead
            set density_ahead 0
            set crossing? false
            set crossing_int -1
            set moved? false
            set arrival_time 0


            ifelse random-float 1 < 0.5 [
              set side 0
            ][
              set side 1
            ]

            if dcsn = 1 [          ; horizontal evacuation on foot
              set color orange
              set path [hor-path] of myself ; myself = current_int of the resident - Note that intersection hold the path infomration
                                            ; which passed to the pedestrians and cars
              set decision 1
            ]
            if dcsn = 3 [          ; vertical evacuation on foot
              set color turquoise
              set path [ver-path] of myself ; myself = current_int of the resident - Note that intersection hold the path infomration
                                            ; which passed to the pedestrians and cars
              set decision 3
            ]
            ifelse empty? path [set shelter -1][set shelter last path] ; if path list is not empty the who of the shelter is the last item of the path
                                                                       ; otherwise, there is no shelter destination, either the current_int is the shelter
                                                                       ; or due to network disconnectivity, there were no path available to any of the shelters
            if shelter = -1 [
              if decision = 1 and [shelter_type] of current_int = "Hor" [set shelter -99]  ; if the decision is horizontal evac and the list is empty since current_int is a horizontal shelter
              if decision = 3 and [shelter?] of current_int [set shelter -99]              ; if the decision is vertical evac and the list is empty since current_int is a shelter
                                                                                           ; basically if shelter = -99, we can mark the pedestrian as evacuated later
            ]

            ifelse [crossroad?] of current_int and not empty? path
            [
              ;; set previous intersection by selecting a random intersection different from the next (init prev_int)
              let next_who [who] of intersection (item 0 path)
              set in_nodes [who] of in_nodes with [who != next_who]
              let prev_int_who item random (length in_nodes) in_nodes
              set prev_int intersection prev_int_who
            ]
            [
              set prev_int current_int
            ]

            st
          ]
          set evacuee_list lput pedestrian _who evacuee_list
        ]
      ]
      if dcsn = 2 or dcsn = 4 [   ; horizontal (2) or vertical (4) evacuation - by CAR
        ask current_int [         ; ask the current intersection of the resident to hatch a car
          let in_nodes in-link-neighbors

          let _who 0
          hatch-cars 1 [
            set _who who
            set id resident_id
            set size 0.5 ; 2
            set current_int myself ; myself = current_int of the resident
            set evacuated? false   ; initialized as not evacuated, will be checked immediately after being born
            set dead? false        ; initialized as not dead, will be checked immediately after being born
            set moving? false      ; initialized as not moving, will start moving immediately after if not evacuated and not dead
            set density_ahead 0
            set crossing? false
            set moved? false
            set waiting? false
            set rightofway? true
            set arrival_time 0

            if dcsn = 2 [          ; horizontal evacuation by car
              set color sky
              set path [hor-path] of myself ; myself = current_int of the resident
              set decision 2
            ]
            if dcsn = 4 [          ; vertical evacuation by car
              set color magenta
              set path [ver-path] of myself ; myself = current_int of the resident
              set decision 4
            ]
            ifelse empty? path [set shelter -1][set shelter last path]       ; if path list is not empty the who of the shelter is the last item of the path
            if shelter = -1 [
              if decision = 2 and [shelter_type] of current_int = "Hor" [set shelter -99] ; if the decision is horizontal evac and the list is empty since current_int is a horizontal shelter
              if decision = 4 and [shelter?] of current_int [set shelter -99]             ; if the decision is vertical evac and the list is empty since current_int is a shelter
                                                                                          ; basically if shelter = -99, we can mark the car as evacuated later
            ]

            ifelse [crossroad?] of current_int and not empty? path
            [
              ;; set previous intersection by selecting a random intersection different from the next (just initialization)
              let next_who [who] of intersection (item 0 path)
              set in_nodes [who] of in_nodes with [who != next_who]
              let prev_int_who item random (length in_nodes) in_nodes
              set prev_int intersection prev_int_who
            ]
            [
              set prev_int current_int
            ]

            st
          ]
          set evacuee_list lput car _who evacuee_list
        ]
      ]
      die
    ][
      ; check the residnet that are on the way if they have been caught by the tsunami
      if [depth] of patch-here > Hc [ set time_in_water time_in_water + tick_to_sec ]
    ]
  ]
end


to pedestrians-behaviour
  ask pedestrians [
    ; check the pedestrians if they have evacuated already or died
    if not evacuated? and not dead? [
      if [who] of current_int = shelter or shelter = -99 [mark-evacuated]
      if [depth] of patch-here >= Hc [set time_in_water time_in_water + tick_to_sec mark-dead]
    ]

    ; set up the pedestrians that should move
    if not moving? and not empty? path and not evacuated? and not dead?[
      if not empty? path [
        set next_int intersection item 0 path   ; assign item 0 of path to next_int

        set path remove-item 0 path             ; remove item 0 of path
        set heading towards next_int            ; set the heading towards the destination
        set moving? true

        ask road ([who] of current_int) ([who] of next_int)[set crowd crowd + 1] ; add the crowd of the road the pedestrian will be on
      ]
    ]

    ; move the pedestrians that should move
    if moving? [
      update-density-ahead-pedestrians
      set speed update-pedestrian-speed free_speed density_ahead

      ;; the agent has entered the crosswalk
      if not moved? and not crossing? and not empty? path and [crossroad?] of next_int and distance next_int < int_width / patch_to_feet / 2 [
        set crossing? true
        set arrival_time int(ticks)

        let X intersection item 0 path
        let next_dir get-next-direction current_int next_int X
        let int-dir map-direction-intersection current_int next_int X

        let key ""
        let new_side 0

        (ifelse
          next_dir = "left" and side = 1 [
            set key table:get int-dir "origin"
            set new_side 0
          ]
          next_dir = "right" and side = 0 [
            set key table:get int-dir "origin"
            set new_side 1
          ]
          next_dir = "straight" [
            ifelse side = 0 [
              set key table:get int-dir "left"
            ][
              set key table:get int-dir "right"
            ]
          ]
        )

        if key != "" [
          ask next_int [
            table:put crossing_counts key (table:get-or-default crossing_counts key 0) + 1
          ]
          set crossing_int key

          ;; update side
          set side new_side
        ]

      ]

      ;; the agent has left the crosswalk
      if moved? and crossing? and [crossroad?] of current_int and distance current_int >= (int_width / 2) / patch_to_feet [
        set crossing? false
        set moved? false

        let key crossing_int
        if crossing_int != -1 [
          ;; remove from the queue
          ask current_int [
            table:put crossing_counts key (table:get-or-default crossing_counts key 0) - 1
          ]

          set crossing_int -1
        ]
      ]

      ifelse speed > distance next_int [fd distance next_int][fd speed] ; move the pedestrian towards the next intersection

      if distance next_int < 0.005 [                                 ; if close enough check if evacuated? dead? if neither, get ready for the next step
        set moving? false

        if [crossroad?] of next_int [
          set moved? true
        ]

        ask road ([who] of current_int) ([who] of next_int)[set crowd crowd - 1] ; decrease the crowd of the road the pedestrian was on
        set prev_int current_int
        set current_int next_int                                                 ; update current intersection
        if [who] of current_int = shelter [
          mark-evacuated
          table:put evacuee_times who ticks
        ]
      ]
    ]
  ]
end


to update-counter [dict key value]
  ; init counters for each tick
  let zeros n-values 3600 [ i -> 0 ]
  let tmp table:get-or-default dict key zeros

  let counter (item (ticks - 1) tmp) + value
  set tmp replace-item (ticks - 1) tmp counter

  table:put dict key tmp
end

to cars-behaviour
  ask cars [
    ; check the cars if they have evacuated already or died
    if not evacuated? and not dead? [
      if [who] of current_int = shelter or shelter = -99 [mark-evacuated]
      if [depth] of patch-here >= Hc [set time_in_water time_in_water + tick_to_sec]
    ]

    ; check again
    if not evacuated? and not dead? [

      ; set up the cars that should move
      if not moving? and not empty? path [
        if not empty? path [
          set next_int intersection item 0 path   ; assign item 0 of path to next_int

          set path remove-item 0 path             ; remove item 0 of path
          set heading towards next_int            ; set the heading towards the destination

          ask road ([who] of current_int) ([who] of next_int)[set traffic traffic + 1] ; add the traffic of the road the car will be on
          set moving? true
        ]
      ]

      ; intersection cars-pedestrians interactions
      ; cars wait for pedestrians crossing
      if crossing? [
        let p_count 0
        let key [who] of current_int

        ifelse not moved? [
          ask next_int [
            set p_count (table:get-or-default crossing_counts key 0)
          ]
        ][
          set key [who] of next_int
          ask current_int [
            set p_count (table:get-or-default crossing_counts key 0)
          ]
        ]

        set waiting? p_count > 0
      ]
    ]

    ; move the cars that should move
    if moving? [
      ifelse rightofway? and not waiting? [
        ;; check on speed to not go over!
        if [crossroad?] of next_int and not moved? and not crossing? [
          let lim_spd distance next_int - (int_width / 2 / patch_to_feet)
          if speed > lim_spd [set speed lim_spd]
        ]

        move-gm                 ; set the speed with general motors car-following model
        fd speed                ; move
      ][
        set speed 0
      ]

      ;; the car has entered the crossroad section
      if not moved? and not crossing? and [crossroad?] of next_int and distance next_int <= (int_width / 2) / patch_to_feet [
        ask next_int [
          set arrival-queue (lput myself arrival-queue) ;; add car to the car-queues
        ]

        set arrival_time int(ticks)
        set crossing? true
        set rightofway? false

        ask road ([who] of current_int) ([who] of next_int)[
          if car-in-t != 0 [
            set car-in-h lput (ticks - car-in-t) car-in-h
          ]

          set car-in-t ticks
        ]
      ]

      ;; if close enough check if evacuated? dead? if neither, get ready for the next step
      if distance next_int < 0.005 [
        set moving? false

        if [crossroad?] of next_int [
          set moved? true;
        ]

        ask road ([who] of current_int) ([who] of next_int)[set traffic traffic - 1] ; decrease the traffic of the road the pedestrian was on
        set prev_int current_int           ; update previous intersection
        set current_int next_int           ; update current intersection

        if [who] of current_int = shelter [
          mark-evacuated
          table:put evacuee_times who ticks
        ]
      ]

      ;; the car has left the crossroad section
      if (moved? and crossing? and [crossroad?] of current_int and distance current_int >= (int_width / 2) / patch_to_feet) [
        ask current_int [
          let index (position myself arrival-queue) ;; get the index of myself in arrival-queue
          if index != false [
            set arrival-queue (remove-item index arrival-queue) ;; remove car from the car-queues]

            set index (position myself crossing-cars)

            if index != false [
              set crossing-cars (remove-item index crossing-cars)
            ]
          ]
        ]

        set crossing? false
        set speed max_speed / fd_to_mph
        set moved? false

        ask road ([who] of current_int) ([who] of next_int)[
          if car-out-t != 0 [
            set car-out-h lput (ticks - car-out-t) car-out-h
          ]

          set car-out-t ticks
        ]
      ]
    ]
  ]
end


to-report get-ped-flow
  let extra_length int_width / 2
  let ped pedestrians with [not crossing? and current_int = [end1] of myself and next_int = [end2] of myself]

  if [crossroad?] of end1 and [crossroad?] of end2 [
    set extra_length extra_length * 2
  ]

  let area (link-length * patch_to_meter - extra_length / 3.281) * side_width * 2 / 3.281

  if count ped = 0 [
    report 0
  ]

  report count ped / area * (mean [speed * fd_to_ftps / 3.281] of ped)
end

to handle-crossing-cars
  if count pedestrians != 0 [
    ask int-roads [
      let flow ifelse-value crowd = 0 [0][get-ped-flow]
      set ped-flow lput flow ped-flow
    ]
  ]

  if count pedestrians != 0 or count cars != 0 [
    ask crossroads [
      ifelse length stops = 2 [
        handle-two-way
      ][
        handle-four-way
      ]
    ]
  ]
end


to handle-opposite-crossing [ints cars-queue]
  let filtered-cars []

  ; let available-cars turtle-set cars-queue with-min [arrival_time]

  ask ints [
    let first-car min-one-of (cars-queue with [current_int = myself]) [distance next_int]

    if first-car != nobody and [not waiting?] of first-car [
      set filtered-cars lput first-car filtered-cars
    ]
  ]

  ifelse length filtered-cars = 2 [
    let origin_car item 0 filtered-cars
    let straight_car item 1 filtered-cars

    ; check conflicts
    let dir1 0
    let dir2 0

    ask origin_car [
      if not empty? path [
        set dir1 get-next-direction current_int next_int (intersection item 0 path)
      ]
    ]

    ask straight_car [
      if not empty? path [
        set dir2 get-next-direction current_int next_int (intersection item 0 path)
      ]
    ]

    ifelse member? (list dir1 dir2) origin_straight [      ; pass together
      set crossing-cars (list origin_car straight_car)
    ][                                                     ; pass who does no go to the left
      ifelse dir1 != "left" [
        set crossing-cars (list origin_car)
      ][
        set crossing-cars (list straight_car)
      ]
    ]
  ][
    set crossing-cars filtered-cars
  ]
end

to handle-two-way
  if length arrival-queue > 0 [
    let queue (turtle-set arrival-queue)

    let stopped queue with [member? current_int [stops] of myself]
    let main queue with [not member? self stopped]

    let principal_ints turtle-set map [x -> intersection x] remove-duplicates [who] of link-neighbors
    set principal_ints principal_ints with [not member? self [stops] of myself]

    let secondary_ints turtle-set stops

    ifelse any? main [
      if empty? crossing-cars [
        handle-opposite-crossing principal_ints main
      ]
    ][
      if any? stopped and empty? crossing-cars [
        handle-opposite-crossing secondary_ints stopped
      ]
    ]

    ask turtle-set crossing-cars [
      set rightofway? true

      ask next_int [
        let exit-time (ticks - [arrival_time] of myself)
        set car-delay (lput exit-time car-delay)
      ]
    ]
  ]
end

to handle-four-way
  if length arrival-queue > 0 [
    if empty? crossing-cars [
      let filtered-cars find-right-of-way

      ;; se 4 auto arrivano nello stesso tempo VERAMENTE IMPROBABILE!!!!

      let dir1 0
      let dir2 0
      let dir3 0

      ;; se manca right -> origin, left, straight
      let origin_car table:get filtered-cars "origin"
      let left_car table:get filtered-cars "left"
      let straight_car table:get filtered-cars "straight"

      if origin_car != nobody [
        ask origin_car [
          if not moved? and not empty? path [
            set dir1 get-next-direction current_int next_int (intersection item 0 path)
          ]
        ]

        if [not waiting?] of origin_car [

          ifelse left_car != nobody [
            ask left_car [
              if not empty? path [
                set dir2 get-next-direction current_int next_int (intersection item 0 path)
              ]
            ]
          ][
            ;; origin - straight
            if straight_car != nobody [
              ask straight_car [
                if not empty? path [
                  set dir3 get-next-direction current_int next_int (intersection item 0 path)
                ]
              ]
            ]

            ifelse dir3 != 0 and [not waiting?] of straight_car and member? (list dir1 dir3) origin_straight [
              set crossing-cars (list origin_car straight_car)
            ][
              set crossing-cars (list origin_car)
            ]
          ]

          ifelse dir2 != 0 and [not waiting?] of left_car and member? (list dir1 dir2) origin_left [
            if straight_car != nobody [
              ask straight_car [
                if not empty? path [
                  set dir3 get-next-direction current_int next_int (intersection item 0 path)
                ]
              ]
            ]

            ifelse dir3 != 0 and [not waiting?] of straight_car and member? (list dir1 dir2 dir3) origin_left_straight [
              set crossing-cars (list origin_car left_car straight_car)
            ][
              set crossing-cars (list origin_car left_car)
            ]
          ][
            set crossing-cars (list origin_car)
          ]
        ]

        ask turtle-set crossing-cars [
          set rightofway? true

          ask next_int [
            let exit-time (int(ticks) - [arrival_time] of myself)
            set car-delay (lput exit-time car-delay)
          ]
        ]
      ]
    ]
  ]
end


to set-casualties
  let who_1 [who] of current_int
  let who_2 [who] of next_int

  if who_1 = who_2 [
    set who_2 who_1
    set who_1 [who] of prev_int
  ]

  ask road who_1 who_2 [ set casualties casualties + 1 ]
end


;######################################
;*************************************#
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;*#
;;;;;;;;;;;;;   PLOT   ;;;;;;;;;;;;;;*#
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;*#
;*************************************#
;######################################


to export-network-data
  ask roads [
    let w1 [who] of end1
    let w2 [who] of end2

    let mean_car_speed 0
    let X cars with [current_int != 0 and next_int != 0]
    let car_speeds_list [speed * fd_to_mph] of X with [road ([who] of current_int) ([who] of next_int) = myself]
    if not empty? car_speeds_list [
      set mean_car_speed mean car_speeds_list
    ]

    let mean_ped_speed 0
    set X pedestrians with [current_int != 0 and next_int != 0]
    let ped_speeds_list [speed * fd_to_ftps] of X with [road ([who] of current_int) ([who] of next_int) = myself]
    if not empty? ped_speeds_list [
      set mean_ped_speed mean ped_speeds_list
    ]

    let row (list w1 w2 traffic crowd int(ticks / 60) mean_car_speed mean_ped_speed casualties)
    set road_data lput row road_data
  ]

  ask crossroads [
    let car-times ifelse-value not empty? car-delay [mean car-delay][0]

    let in-roads link-set map [x -> road x who] ([who] of in-link-neighbors)
    let out-roads link-set map [x -> road who x] ([who] of out-link-neighbors)

    let pinflow [list ([who] of end1) (ifelse-value not empty? ped-flow [mean ped-flow][0])] of in-roads
    let poutflow [list ([who] of end2) (ifelse-value not empty? ped-flow [mean ped-flow][0])] of out-roads

    let carinflow [list ([who] of end1) (ifelse-value not empty? car-in-h [1 / mean car-in-h][0])] of in-roads
    let caroutflow [list ([who] of end2) (ifelse-value not empty? car-out-h [1 / mean car-out-h][0])] of out-roads

    let row (list who car-times carinflow caroutflow pinflow poutflow int(ticks / 60))
    set intersection_data lput row intersection_data
  ]

  if ticks = 3600 [
    ask intersections [
      let agents turtle-set evacuee_list
      let car-ev_times [table:get-or-default evacuee_times who -1] of agents with [is-car? self]
      let ped-ev_times [table:get-or-default evacuee_times who -1] of agents with [is-pedestrian? self]

      set car-ev_times remove -1 car-ev_times
      set ped-ev_times remove -1 ped-ev_times

      set car-avg_ev_times ifelse-value not empty? car-ev_times [mean car-ev_times][0]
      set ped-avg_ev_times ifelse-value not empty? ped-ev_times [mean ped-ev_times][0]

      let row (list who car-avg_ev_times ped-avg_ev_times)
      set intersection_times lput row intersection_times
    ]
  ]
end


to import-network-data
  ; setup
  reset-ticks
  load1
  ask intersections with [shelter?] [set size 0]
  ask roads [set thickness 0.5]

  ; read csv
  let suffix (word R1_HorEvac_Foot "-" R2_HorEvac_Car "-" iteration ".csv")
  let rows csv:from-file (word "./plot_results/data/roads/roads-" suffix)
  set rows remove-item 0 rows

  foreach rows [x ->
    if item 4 x = 20 [
      ask road item 0 x item 1 x [
        set traffic item 2 x
        set crowd item 3 x
        set car_mean_speed item 5 x
        set ped_mean_speed item 6 x
        set casualties item 7 x
      ]
    ]
  ]

  set rows csv:from-file (word "./plot_results/data/intersections/intersections-" suffix)
  set rows remove-item 0 rows

  ask crossroads [
    set car-in-flow table:make
    set car-out-flow table:make
    set ped-in-flow table:make
    set ped-out-flow table:make
  ]

  foreach rows [x ->
    if item 6 x = 60 [

      let carinflow read-from-string (item 2 x)
      let caroutflow read-from-string (item 3 x)
      let pinflow read-from-string (item 4 x)
      let poutflow read-from-string (item 5 x)

      ask intersection item 0 x [
        set car-delay item 1 x
        set car-in-flow table:from-list carinflow
        set car-out-flow table:from-list caroutflow
        set ped-in-flow table:from-list pinflow
        set ped-out-flow table:from-list poutflow
      ]
    ]
  ]

  set rows csv:from-file (word "./plot_results/data/intersections/intersections-evtimes-" suffix)
  set rows remove-item 0 rows

  foreach rows [x ->
    ask intersection item 0 x [
      set car-avg_ev_times item 1 x
      set ped-avg_ev_times item 2 x
    ]
  ]
end


to view-evacuation-time-ss
  ; reset
  ask patches [ set pcolor white ]

  let color-list [[100 100 100] [0 100 100]]

  let ps 8 ; box size
  let xs n-values (world-width / ps + 1) [i -> i - int(world-width / ps / 2)]
  let ys n-values (world-height / ps + 1) [i -> i - int(world-height / ps / 2)]

  foreach xs [ x ->
    foreach ys [ y ->
      let box patches with [pxcor > x * ps and pxcor <= x * ps + ps and pycor > y * ps and pycor <= y * ps + ps]
      let ints intersections-on box

      if any? ints [
        let int_whos [[who] of turtle-set evacuee_list] of ints

        let total []
        foreach int_whos [whos ->
          foreach whos [w ->
            if table:has-key? evacuee_times w [
              set total lput table:get evacuee_times w total
            ]
          ]
        ]

        if not empty? total [
          let c palette:scale-gradient-hsb color-list (mean total) 0 3600
          ask box [set pcolor c]
        ]
      ]
    ]
  ]
end

to view-evacuation-time [agent-type]
  let color-list [[100 100 100] [0 100 100]]

  ask intersections with [shelter?] [set size 0]

  ask intersections [
    let value ifelse-value agent-type = "cars" [car-avg_ev_times][ped-avg_ev_times]
    let col palette:scale-gradient-hsb color-list value 0 3000
    set color col
    set size 5
  ]
end

;;; roads analysis

to view-road-speed [agent-type]
  ask roads [set color gray]

  let color-list [[100 100 100] [0 100 100]]
  let max-n free_flow_speed

  ifelse agent-type = "cars" [
    set max-n max_speed

    ask roads with [car_mean_speed != 0] [
      let n car_mean_speed * 1.609
      let col palette:scale-gradient-hsb color-list n 0 max-n
      set color col
    ]
  ][
    ask roads  with  [ped_mean_speed != 0] [
      let n ped_mean_speed / 3.281
      let col palette:scale-gradient-hsb color-list n 0 max-n
      set color col
    ]
  ]

  ifelse agent-type = "cars" [
    ask roads with [car_mean_speed = 0] [
      let inverse road ([who] of end2) ([who] of end1)
      if inverse != nobody [
        set color [color] of inverse
      ]
    ]
  ][
    ask roads with [ped_mean_speed = 0] [
      let inverse road ([who] of end2) ([who] of end1)
      if inverse != nobody [
        set color [color] of inverse
      ]
    ]
  ]

  print (word 0 ": " item 0 color-list ", " max-n ": "  item 1 color-list)
end

to view-road-traffic [agent-type density?]
  let color-list [[100 100 100] [300 100 100]]
  let max-n max [crowd] of roads

  if agent-type = "cars" [
    set max-n max [traffic] of roads
  ]

  let max_len max [link-length] of roads * patch_to_meter
  let tmp max-n
  ask roads [
    let n 0

    let len link-length * patch_to_meter
    let wid 0

    ifelse agent-type = "cars" [
      set n traffic
      set wid (lane_width / 3.281)
    ][
      set n crowd
      set wid ((side_width * 2) / 3.281)
    ]

    if density? [
      set n (n / (len * wid))
      set tmp max-n / (max_len * wid)
    ]

    let col palette:scale-gradient-hsb color-list n 0 tmp
    set color col
    set thickness 0.5
  ]

  ifelse agent-type = "cars" [
    ask roads with [traffic = 0] [
      let inverse road ([who] of end2) ([who] of end1)
      if inverse != nobody [
        set color [color] of inverse
        set thickness 0.5
      ]
    ]
  ][
    ask roads with [crowd = 0] [
      let inverse road ([who] of end2) ([who] of end1)
      if inverse != nobody [
        set color [color] of inverse
        set thickness 0.5
      ]
    ]
  ]

  print (word 0 ": " item 0 color-list ", " tmp ": "  item 1 color-list)

  let warnings []
  ifelse agent-type = "cars" [
    ask roads with [traffic != 0] [let inverse road ([who] of end2) ([who] of end1) if inverse != nobody [ if [traffic] of inverse != 0 [ set warnings lput self warnings  ] ] ]
  ][
    ask roads with [crowd != 0] [let inverse road ([who] of end2) ([who] of end1) if inverse != nobody [ if [crowd] of inverse != 0 [ set warnings lput self warnings ] ] ]
  ]
  if length warnings != 0 [
    print "WARNING: traffic in opposite direction on the same link"
    print warnings
  ]
end

to view-critical-links
  ask int-roads [
    set color gray
    set thickness 0.5
  ]

  let total sum [casualties] of int-roads

  ask int-roads [
    let perc casualties / total * 100

    if perc >= 5 [
      set color red
      set thickness 2
    ]
  ]

  ask int-roads with [casualties = 0] [
    let inverse road ([who] of end2) ([who] of end1)
    if inverse != nobody [
      set color [color] of inverse
    ]
  ]
end


to view-micro-level-speed [ped? car?]
  ask patches [set pcolor black]
  ask intersections with [not shelter?] [set color white]
  ask intersections with [shelter?] [set color violet]
  ask roads [set color white]

  let color-list [[0 100 100] [100 100 100]] ;[0 100 100]

  if car? [
    let max-n max_speed
    ask cars [
      let spd speed * fd_to_mph * 1.609
      let col palette:scale-gradient-hsb color-list spd 0 max-n
      set color col
      set size 3
    ]
  ]

  if ped? [
    let max-n free_flow_speed
    ask pedestrians [
      let spd speed * fd_to_ftps / 3.281;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
      let col palette:scale-gradient-hsb color-list spd 0 max-n
      set color col
      set size 3
    ]
  ]

  ask residents [set size 0]
  if ped? and not car? [ask cars [set size 0]]
  if not ped? and car? [ask pedestrians [set size 0]]

end

;;; intersections analysis

to view-intersection-car-delay
  ask patches [set pcolor white]
  ask intersections [set size 0]

  let color-list [[100 100 100] [0 100 100]]

  let max-n max [car-delay] of crossroads

  ask crossroads with [not empty? stops] [set shape "circle" set size 3]
  ask crossroads with [empty? stops] [set shape "x" set size 6]

  ask crossroads [
    let col palette:scale-gradient-hsb color-list car-delay 0 max-n
    set color col
  ]

  ask residents [set size 0]
  ask cars [set size 0]
  ask pedestrians [set size 0]
end

to view-intersection-flow [flow-dir agent-type]
  ask patches [set pcolor white]
  let color-list [[100 100 100] [0 100 100]]
  let tmp list max [sum table:values car-in-flow] of crossroads max [sum table:values car-out-flow] of crossroads
  print tmp

  if agent-type = "pedestrian" [
    set tmp list max [sum table:values ped-in-flow] of crossroads max [sum table:values ped-out-flow] of crossroads
  ]

  let max-n max tmp

  ask intersections [set size 0] ; hide non-crossroads

  ask crossroads [
    let flow ifelse-value flow-dir = "in" [car-in-flow][car-out-flow]

    if agent-type = "pedestrian" [
      set flow ifelse-value flow-dir = "in" [ped-in-flow][ped-out-flow]
    ]

    let col palette:scale-gradient-hsb color-list (sum table:values flow) 0 max-n

    set size 4
    set color col
    set shape "circle"
  ]

  ask residents [set size 0]
  ask cars [set size 0]
  ask pedestrians [set size 0]

  print max-n
end


to profile
  reset-ticks
  load1
  load2                                          ;; set up the model
  profiler:start                                 ;; start profiling
  repeat 60 * 60 [ go ]                          ;; run something you want to measure
  profiler:stop                                  ;; stop profiling
  csv:to-file "profiler_data.csv" profiler:data  ;; save the results
  profiler:reset                                 ;; clear the data
end
@#$#@#$#@
GRAPHICS-WINDOW
228
11
940
724
-1
-1
3.5025
1
10
1
1
1
0
0
0
1
-100
100
-100
100
1
1
1
ticks
30.0

PLOT
946
342
1370
495
Percentage of Evacuated
Min
%
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Evacuated" 1.0 0 -10899396 true "" "plotxy (ticks / 60) (count turtles with [ color = green ] / (count residents + count pedestrians + count cars) * 100)"
"Cars" 1.0 0 -13345367 true "" "plotxy (ticks / 60) (count cars with [ color = green ] / (count residents + count pedestrians + count cars) * 100)"
"Pedestrians" 1.0 0 -14835848 true "" "plotxy (ticks / 60) (count pedestrians with [ color = green ] / (count residents + count pedestrians + count cars) * 100)"

SWITCH
67
13
221
46
immediate_evacuation
immediate_evacuation
1
1
-1000

BUTTON
1294
10
1373
43
GO
\ngo
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
8
54
217
82
Residents' Decision Making Probabalisties : (Percent)
11
0.0
1

INPUTBOX
8
87
109
147
R1_HorEvac_Foot
50.0
1
0
Number

INPUTBOX
8
150
109
210
R3_VerEvac_Foot
0.0
1
0
Number

MONITOR
947
53
1029
98
Time (min)
ticks / 60
1
1
11

INPUTBOX
113
214
163
274
Hc
1.0
1
0
Number

PLOT
945
158
1370
332
Percentage of Casualties
Min
%
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Dead" 1.0 0 -2674135 true "" "plotxy (ticks / 60) (count turtles with [color = red] / (count residents + count pedestrians + count cars) * 100)"
"Cars" 1.0 0 -5825686 true "" "plotxy (ticks / 60) (count cars with [color = red] / (count residents + count pedestrians + count cars) * 100)"
"Pedestrians" 1.0 0 -955883 true "" "plotxy (ticks / 60) ((count pedestrians with [color = red] + count residents with [color = red]) / (count residents + count pedestrians + count cars) * 100)"

BUTTON
946
12
1022
45
READ (1/2)
load1\noutput-print \"READ (1/2) DONE!\"\nbeep
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
5
215
121
257
Critical Depth and Time: (Meters and Seconds)
11
0.0
1

INPUTBOX
6
484
56
544
Rtau1
10.0
1
0
Number

INPUTBOX
56
484
106
544
Rsig1
1.65
1
0
Number

INPUTBOX
6
548
56
608
Rtau3
10.0
1
0
Number

INPUTBOX
56
548
106
608
Rsig3
1.65
1
0
Number

TEXTBOX
8
468
208
496
Evacuation Decsion Making Times:
11
0.0
1

MONITOR
1037
53
1119
98
Evacuated
count turtles with [ color = green ]
17
1
11

MONITOR
1128
53
1205
98
Casualty
count turtles with [ color = red ]
17
1
11

MONITOR
1072
105
1166
150
Mortality (%)
mortality_rate
2
1
11

BUTTON
1223
10
1289
43
Read (2/2)
load2\noutput-print \"READ (2/2) DONE!\"\nbeep
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
1122
10
1218
43
Place Verticals
pick-verticals
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
1213
53
1293
98
Vertical Cap
sum [evacuee_count] of intersections with [shelter? and shelter_type = \"Ver\"]
17
1
11

INPUTBOX
117
87
217
147
R2_HorEvac_Car
50.0
1
0
Number

INPUTBOX
117
150
217
210
R4_VerEvac_Car
0.0
1
0
Number

INPUTBOX
112
484
162
544
Rtau2
10.0
1
0
Number

INPUTBOX
162
484
212
544
Rsig2
1.65
1
0
Number

INPUTBOX
114
549
164
609
Rtau4
10.0
1
0
Number

INPUTBOX
161
549
211
609
Rsig4
1.65
1
0
Number

INPUTBOX
64
285
135
345
max_speed
35.0
1
0
Number

TEXTBOX
11
285
51
313
by car:\n(mph)
11
0.0
1

INPUTBOX
64
346
137
406
acceleration
5.0
1
0
Number

INPUTBOX
141
346
216
406
deceleration
25.0
1
0
Number

TEXTBOX
6
358
55
392
(ft/s^2)
11
0.0
1

INPUTBOX
64
407
137
467
alpha
0.14
1
0
Number

TEXTBOX
3
421
63
462
(mi^2/hr)
11
0.0
1

BUTTON
1028
11
1116
44
Break Links
break-links
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
7
14
62
47
Initialize
setup-init-val
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
947
504
1370
725
Evacuation Time Histogram
Minutes (after the earthquake)
#
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Histogram" 1.0 1 -16777216 true "set-plot-x-range 0 60\nset-plot-y-range 0 count turtles with [ color = green ]\nset-histogram-num-bars 60\nset-plot-pen-mode 1 ; bar mode" "if enable-plots [histogram ev_times]"
"Mean" 1.0 0 -10899396 true "set-plot-pen-mode 0 ; line mode" "plot-pen-reset\nplot-pen-up\nplotxy mean ev_times 0\nplot-pen-down\nplotxy mean ev_times plot-y-max"
"Median" 1.0 0 -2674135 true "set-plot-pen-mode 0 ; line mode" "plot-pen-reset\nplot-pen-up\nplotxy median ev_times 0\nplot-pen-down\nplotxy median ev_times plot-y-max"

MONITOR
949
105
1065
150
Per Evacuated (%)
count turtles with [ color = green ] / (count residents + count pedestrians + count cars) * 100
1
1
11

INPUTBOX
166
213
216
273
Tc
120.0
1
0
Number

PLOT
1384
10
1793
162
pedestrian density-speed
p/m²
m/s
0.0
8.0
0.0
1.34
false
true
"" ""
PENS
"simulation" 1.0 2 -13791810 true "" ";;plotxy\n;;  ((mean [density_ahead] of pedestrians with [moving?]) * 11.625)\n;;  ((mean [speed] of pedestrians with [moving?]) * fd_to_ftps / 3.281)\n\nif enable-plots [;and ticks mod 200 = 0 [\n  ask pedestrians with [dead? = false][;; and (precision (free_speed * fd_to_ftps / 3.281) 2) = 1.21] [\n    plotxy (density_ahead) (speed * patch_to_meter)\n  ]\n]\n"

PLOT
1384
169
1794
318
pedestrian density-flow
p/m²
p/s
0.0
8.0
0.0
2.0
false
true
"" ""
PENS
"simulation" 1.0 2 -13791810 true "" ";;plotxy\n;;  ((mean [density_ahead] of pedestrians with [moving?]) * 11.625)\n;;  ((mean [speed] of pedestrians with [moving?]) * fd_to_ftps / 3.281)\n\nif enable-plots andticks mod 200 = 0 [\n  ask pedestrians with [dead? = false][; and (precision (free_speed * fd_to_ftps / 3.281) 2) = 1.21] [\n    plotxy (density_ahead) (speed * fd_to_ftps / 3.281) * (density_ahead)\n  ]\n]\n"

INPUTBOX
122
616
221
676
gamma
1.913
1
0
Number

INPUTBOX
3
679
119
739
jam_density
5.4
1
0
Number

PLOT
1384
326
1795
446
waiting pedestrian crossing
Min
%
0.0
60.0
0.0
0.0
true
true
"" ""
PENS
"crossing ped" 1.0 0 -955883 true "" "if enable-plots [\nlet total count pedestrians with [not evacuated? and not dead?]\nifelse total = 0 [ \n ;  plotxy int(ticks) 0\n][\n ; plotxy int(ticks) count pedestrians with [crossing?] / total * 100\n]\n]"
"cars waiting peds" 1.0 0 -13791810 true "" "if enable-plots [\nlet total count cars\nifelse total = 0 [ \n   plotxy int(ticks) 0\n][\n  plotxy int(ticks) count cars with [waiting? and not rightofway?] / total  * 100\n]\n]"
"cars waiting cars" 1.0 0 -13840069 true "" "if enable-plots [\nlet total count cars\nifelse total = 0 [ \n   plotxy int(ticks) 0\n][\n  plotxy int(ticks) count cars with [not waiting? and not rightofway?] / total  * 100\n]\n]"

INPUTBOX
3
616
119
676
free_flow_speed
1.34
1
0
Number

INPUTBOX
1386
609
1509
669
iteration
1.0
1
0
Number

BUTTON
1385
674
1510
721
Multiple Runs
ifelse iteration <= 30 [  \n  if ticks = 0 and iteration = 1 [\n    reset-ticks\n    load1\n    load2\n  ]\n\n  go\n  \n  if ticks != 0 and ticks mod (20 * 60) = 0 [\n     export-network-data\n  ]\n\n  if ticks = 3600 [\n    let suffix (word R1_HorEvac_Foot \"-\" R2_HorEvac_Car \"-\" iteration \".csv\")\n  \n    ; export plot\n    export-plot \"Percentage of Evacuated\" (word \"./plot_results/data/evacuated/evacuated-\" suffix)\n    export-plot \"Percentage of Casualties\" (word \"./plot_results/data/casualties/casualties-\" suffix)\n    export-plot \"Evacuation Time Histogram\" (word \"./plot_results/data/times/times-\" suffix)\n    \n    ; export network data\n    csv:to-file (word \"./plot_results/data/roads/roads-\" suffix) road_data\n    csv:to-file (word \"./plot_results/data/intersections/intersections-\" suffix) intersection_data\n    csv:to-file (word \"./plot_results/data/intersections/intersections-evtimes-\" suffix) intersection_times\n  \n    set iteration iteration + 1 \n    reset-ticks\n  \n    load1\n    load2\n  ]\n][\n  stop\n]
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
1518
623
1648
656
enable-plots
enable-plots
1
1
-1000

BUTTON
1517
670
1646
716
Reset
reset-ticks\nset iteration 1
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
1384
453
1795
573
plot 1
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"pen-0" 1.0 0 -7500403 true "" ";plot count intersections with [length crossing-cars > 1]"

@#$#@#$#@
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.2.2
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="Exp" repetitions="5" runMetricsEveryStep="false">
    <setup>pre-read
turn-vertical intersection vertical_shelter_num
read-all</setup>
    <go>go</go>
    <metric>count turtles with [color = red] / (count residents + count pedestrians) * 100</metric>
    <metric>count turtles with [color = green and distance one-of intersections with [gate? and gate-type = "Ver"] &lt; 0.01]</metric>
    <enumeratedValueSet variable="tsunami-case">
      <value value="&quot;250yrs&quot;"/>
      <value value="&quot;500yrs&quot;"/>
      <value value="&quot;1000yrs&quot;"/>
      <value value="&quot;2500yrs&quot;"/>
      <value value="&quot;5000yrs&quot;"/>
      <value value="&quot;10000yrs&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="immediate-evacuation">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Hc">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="R3-VerEvac-Foot">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Ped-Speed">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Ped-Sigma">
      <value value="0.65"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Rtau3">
      <value value="0"/>
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
      <value value="4"/>
      <value value="5"/>
      <value value="6"/>
      <value value="7"/>
      <value value="8"/>
      <value value="9"/>
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Rsig3">
      <value value="1.65"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="vertical_shelter_num">
      <value value="82"/>
      <value value="74"/>
      <value value="486"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

prova
0.0
-0.2 1 1.0 0.0
0.0 1 4.0 4.0
0.2 1 1.0 0.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

road
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
@#$#@#$#@
0
@#$#@#$#@
