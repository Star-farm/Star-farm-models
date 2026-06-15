
global {
    int my_param <- 0;
    init {
        write "Hello from GAMA! my_param is " + my_param;
    }
    reflex end_sim when: cycle > 10 {
        do pause;
    }
}

experiment test_exp type: batch until: cycle > 10 {
    parameter "my_param" var: my_param;
}
