generate_results_files <- function(param_group, model_options, 
                                   complem_info, res_it2,
                                   sitNames_corresp, 
                                   sim_default, sim_it1, sim_it2, 
                                   obs_list, converted_obs_list,
                                   obsVar_units, obsVar_used, 
                                   template_path, out_dir, test_case, variety,
                                   varNames_corresp, resVar_names, 
                                   forced_param_values, file_type="numerical",
                                   use_obs_synth=FALSE, sim_true=NULL, 
                                   descr_ref_date=NULL, flag_eos=FALSE) {

  # Tables of parameters for each iteration
  # ---------------------------------------
  
  group_names <- setNames(
    unlist(lapply(strsplit(names(unlist(param_group)), split="[.]"),function(x) x[1])),
    nm=unlist(param_group))

  ## Iteration 1
  Table <- NULL        
  for (gr in names(param_group)) {
    load(file.path(out_dir,"Iteration1",paste0("group_",gr),"optim_results.Rdata"))
    Table_gr <- generate_parameters_table(res, group_names, forced_param_values)
    Table <- bind_rows(Table, Table_gr)
  }
  save_table(table=Table, table_name="Table_parameters_Iteration1", path=out_dir)

  ## Iteration 2
  load(file.path(out_dir,"Iteration2","optim_results.Rdata"))
  Table <- generate_parameters_table(res, group_names, forced_param_values)
  save_table(table=Table, 
             table_name="Table_parameters_Iteration2", 
             path=out_dir)


  # Tables of steps for each iteration
  # ----------------------------------
  
  ## Iteration 1
  
  ### List the results files for each group and step
  dirs <- list.dirs(file.path(out_dir,"Iteration1"))
  files <- list.files(path=dirs, pattern="optim_results.Rdata", full.names = TRUE)          
  files <- lapply(group_names, function(x) {
    if (length(grep(x,files))>1) {
      return(files[grep(x,files)[-1]])
    } else {
      return(files[grep(x,files)])
    }
  })
  names(files) <- group_names
  
  Table <- NULL        
  for (gr in names(param_group)) {
    
    Table_gr <- lapply(files[[gr]], function(x) {
      load(x)
      setNames(
        tibble(gr,
               list(names(res$final_values)),
               nrow(res$init_values),
               filter(res$params_and_crit,rep==res$ind_min_crit)$crit[1],
               res$min_crit_value,
               res$AICc,
               nrow(res$params_and_crit),
               NA,
               ""),
        nm=c("Name of the group","Name of the estimated parameters",
             "Number of starting values",
             "Initial value of the minimized criterion",
             "Final value of the minimized criterion",
             "Final AICc", "Total number of calls to model",
             "Simulation time (h)",
             "Selected step")
      )
    })
    Table_gr <- bind_rows(Table_gr)
    Table_gr[Table_gr[,"Final AICc"]==min(Table_gr[,"Final AICc"]),"Selected step"] <- "X"
    load(file.path(out_dir,"Iteration1",paste0("group_",gr),"optim_results.Rdata"))
    Table_gr[nrow(Table_gr),"Simulation time (h)"] <- res$total_time/3600
    Table <- bind_rows(Table, Table_gr)
      
  }
  save_table(table=Table, table_name="Table_steps_Iteration1", path=out_dir)
  
  
  ## Iteration 2
  load(file.path(out_dir,"Iteration2","optim_results.Rdata"))
  estimated_parameters <- names(res$final_values)
  Table <- setNames(
    tibble(list(names(res$final_values)),
           nrow(res$init_values),
           filter(res$params_and_crit,rep==res$ind_min_crit)$crit[1],
           res$min_crit_value,
           nrow(res$params_and_crit),
           res$total_time/3600),
    nm=c("Name of the estimated parameters",
         "Number of starting values",
         "Initial value of the minimized criterion",
         "Final value of the minimized criterion",
         "Total number of calls to model",
         "Simulation time (h)")
  )
  save_table(table=Table, 
             table_name="Table_steps_Iteration2", 
             path=out_dir)
  


  # Tables of stats per variable for each iteration
  # -----------------------------------------------
  
  ## Compute stats for the simulation results obtained from default values of the parameters
  crit_names <- c("SS_res","Bias","RMSE","EF","Bias2","SDSD","LCS")
  sim_list_converted_default <- convert_and_rename(sim_default$sim_list, 
                                                   sitNames_corresp, simVar_units, 
                                                   varNames_corresp, obsVar_units)
  stats_default <- summary(sim_list_converted_default, obs=obs_list, stats=crit_names) %>%
    dplyr::select(-group, -situation) %>%
    dplyr::rename(SSE=SS_res, Efficiency=EF) %>%
    dplyr::rename_with(~paste("Default",.x))
  names(stats_default)[1] <- "Name of the variable"

  ## Compute stats criteria for the transformed variable
  transform_var_converted <- NULL
  if (!is.null(transform_var)) {
    transform_var_converted <- transform_var
    names(transform_var_converted) <- 
      names(varNames_corresp)[match(names(transform_var),varNames_corresp)]
    obs_list_transformed <- apply_transform_var(obs_list, transform_var_converted)
    sim_list_default_transformed <- apply_transform_var(sim_list_converted_default, transform_var_converted)
    stats_transformed <- summary(sim_list_default_transformed, obs=obs_list_transformed, stats=crit_names) %>%
      dplyr::select(-group, -situation) %>%
      dplyr::rename(SSE=SS_res, Efficiency=EF) %>%
      dplyr::filter(variable %in% names(transform_var_converted)) %>%
      dplyr::rename_with(~paste("Default",.x))
    names(stats_transformed)[1] <- "Name of the variable"
    stats_transformed$`Name of the variable` <- 
      paste0("log(",stats_transformed$`Name of the variable`,")")
    stats_default <- dplyr::union(stats_default, stats_transformed)
  }
  
  for (it in c("1", "2")) {
 
    if (it=="3") {
      sim <- sim_final
    } else {
      eval(parse(text=paste0("sim <- sim_it",it)))
    }
    sim_list_converted <- convert_and_rename(sim$sim_list, sitNames_corresp, simVar_units, 
                                   varNames_corresp, obsVar_units)
    
    # Compute stats criteria
    stats <- summary(sim_list_converted, obs=obs_list, stats=crit_names) %>%
      dplyr::select(-group, -situation) %>%
      dplyr::rename(SSE=SS_res, Efficiency=EF) %>%
      dplyr::rename_with(~paste("Final",.x))
    names(stats)[1] <- "Name of the variable"

    # Compute stats criteria for the transformed variable
    if (!is.null(transform_var)) {
      sim_list_transformed <- apply_transform_var(sim_list_converted, transform_var_converted)
      stats_transformed <- summary(sim_list_transformed, obs=obs_list_transformed, stats=crit_names) %>%
        dplyr::select(-group, -situation) %>%
        dplyr::rename(SSE=SS_res, Efficiency=EF) %>%
        dplyr::filter(variable %in% names(transform_var_converted)) %>%
        dplyr::rename_with(~paste("Final",.x))
      names(stats_transformed)[1] <- "Name of the variable"
      stats_transformed$`Name of the variable` <- 
        paste0("log(",stats_transformed$`Name of the variable`,")")
      stats <- dplyr::union(stats, stats_transformed)
    }

    # Compute weighted SSE per variable for iteration 2
    if (it != "1") {
      eval(parse(text=paste0("model_error_sd <- complem_info$it",it,"$weight")))
      simVar_units_square <- paste(simVar_units,simVar_units)
      names(simVar_units_square) <- names(simVar_units)
      model_error_sd <- bind_cols(lapply(names(model_error_sd), 
                                         function(x) { units(model_error_sd[[x]]) <- simVar_units[x]; model_error_sd[x]}))
      names(model_error_sd) <- names(varNames_corresp)[match(names(model_error_sd),varNames_corresp)]
      model_error_sd_converted <- 
        bind_cols(lapply(names(model_error_sd), function(x) {
          # only convert weights of non-transformed variables (weight of log-transformed variables is the same whatever the dimension)
          if ( !(x %in% names(transform_var_converted)) ) {   
            units(model_error_sd[[x]]) <- obsVar_units[x]; model_error_sd[x]
          }
          model_error_sd[x]
        }))
      names(model_error_sd_converted)[match(names(transform_var_converted),names(model_error_sd_converted))] <- 
        paste0("log(",names(transform_var_converted),")")
      model_error_sd_converted[setdiff(stats[["Name of the variable"]], names(model_error_sd_converted))] <- NA
      stats <- mutate(stats, 
                      `Default Weighted SSE`=as.numeric(stats_default[["Default SSE"]] / (model_error_sd_converted[stats[["Name of the variable"]]])^2 ),
                      `Final Weighted SSE`=as.numeric(stats[["Final SSE"]] / (model_error_sd_converted[stats[["Name of the variable"]]])^2 ))
      ordered_columns <- c("Name of the variable", "Unit", "Default SSE", "Final SSE",
                           "Default Weighted SSE", "Final Weighted SSE", "Default Bias",
                           "Final Bias",	"Default RMSE",	"Final RMSE",	"Default Efficiency",
                           "Final Efficiency", "Default Bias2", "Final Bias2", 
                           "Default SDSD", "Final SDSD", "Default LCS", "Final LCS")
    } else {
      ordered_columns <- c("Name of the variable", "Unit", "Default SSE", "Final SSE",
                           "Default Bias",
                           "Final Bias",	"Default RMSE",	"Final RMSE",	"Default Efficiency",
                           "Final Efficiency", "Default Bias2", "Final Bias2", 
                           "Default SDSD", "Final SDSD", "Default LCS", "Final LCS")
    }
    
    # Add unit column
    stats$Unit <- obsVar_units[stats[["Name of the variable"]]]
    # Rename columns
    # Intercalate Default and final values
    #### Join the Table and relocate columns
    stats_all <- dplyr::full_join(stats, stats_default, by="Name of the variable") %>% 
      dplyr::relocate(dplyr::all_of(ordered_columns))
 
    save_table(table=stats_all, table_name=paste0("Table_variables_Iteration",it), 
               path=out_dir)
    
    # write.table(stats_all, 
    #             file = file.path(out_dir,paste0("Table_variables_Iteration",it,".txt")),
    #             row.names = FALSE, quote=FALSE)
    
  }

    
  # Generate cal_4_results_* files 
  # ------------------------------
  
  # for each iteration plus default values
  # Results at maturity are extracted at observed date or 31/12/HarvestYear
  # in case flag_eos is activated
  suffix <- NULL
  if (!flag_eos) suffix <- "_obs_mat"
  generate_cal_results(sim_default, obs_list, obsVar_units, obsVar_used, 
                       sitNames_corresp, template_path, out_dir, test_case, 
                       variety, varNames_corresp, resVar_names, paste0("default_values",suffix),
                       use_obs_synth=use_obs_synth, sim_true=sim_true, 
                       descr_ref_date=descr_ref_date, flag_obs_mat=TRUE, flag_eos=flag_eos)
  generate_cal_results(sim_it1, obs_list, obsVar_units, obsVar_used, 
                       sitNames_corresp, template_path, out_dir, test_case, 
                       variety, varNames_corresp, resVar_names, paste0(file_type,"_it1",suffix),
                       use_obs_synth=use_obs_synth, sim_true=sim_true, 
                       descr_ref_date=descr_ref_date, flag_obs_mat=TRUE, flag_eos=flag_eos)
  generate_cal_results(sim_it2, obs_list, obsVar_units, obsVar_used, 
                       sitNames_corresp, template_path, out_dir, test_case, 
                       variety, varNames_corresp, resVar_names,  paste0(file_type,"_it2",suffix),
                       use_obs_synth=use_obs_synth, sim_true=sim_true, 
                       descr_ref_date=descr_ref_date, flag_obs_mat=TRUE, flag_eos=flag_eos)
  

  # Same but results at maturity are extracted at simulated date (in case flag_eos not activated, as complementary results)
  if (!flag_eos) {
    suffix <- "_simulated_mat"
    generate_cal_results(sim_default, obs_list, obsVar_units, obsVar_used, 
                         sitNames_corresp, template_path, out_dir, test_case, 
                         variety, varNames_corresp, resVar_names, paste0("default_values",suffix),
                         use_obs_synth=use_obs_synth, sim_true=sim_true, 
                         descr_ref_date=descr_ref_date, flag_obs_mat=FALSE, flag_eos=flag_eos)
    generate_cal_results(sim_it1, obs_list, obsVar_units, obsVar_used, 
                         sitNames_corresp, template_path, out_dir, test_case, 
                         variety, varNames_corresp, resVar_names, paste0(file_type,"_it1",suffix),
                         use_obs_synth=use_obs_synth, sim_true=sim_true, 
                         descr_ref_date=descr_ref_date, flag_obs_mat=FALSE, flag_eos=flag_eos)
    generate_cal_results(sim_it2, obs_list, obsVar_units, obsVar_used, 
                         sitNames_corresp, template_path, out_dir, test_case, 
                         variety, varNames_corresp, resVar_names,  paste0(file_type,"_it2",suffix),
                         use_obs_synth=use_obs_synth, sim_true=sim_true, 
                         descr_ref_date=descr_ref_date, flag_obs_mat=FALSE, flag_eos=flag_eos)
  }


  # Generate daily output files
  # ---------------------------
  
  daily_outdir <- file.path(out_dir,"DailyOutputs")
  if (!dir.exists(daily_outdir)) dir.create(daily_outdir)
  
  # default
  daily_outdir_default <- file.path(daily_outdir,"Default")
  if (!dir.exists(daily_outdir_default)) dir.create(daily_outdir_default)
  for (sit in names(sim_default$sim_list_converted)) {
    write.table(sim_default$sim_list_converted[[sit]],
                file = file.path(daily_outdir_default, paste0("sit",sit,".txt")), 
                quote=FALSE, row.names = FALSE)
  }  
  
  # it1
  daily_outdir_it1 <- file.path(daily_outdir,"Iteration1")
  if (!dir.exists(daily_outdir_it1)) dir.create(daily_outdir_it1)
  for (sit in names(sim_it1$sim_list_converted)) {
    write.table(sim_it1$sim_list_converted[[sit]],
                file = file.path(daily_outdir_it1, paste0("sit",sit,".txt")), 
                quote=FALSE, row.names = FALSE)
  }
  
  # it2
  daily_outdir_it2 <- file.path(daily_outdir,"Iteration2")
  if (!dir.exists(daily_outdir_it2)) dir.create(daily_outdir_it2)
  for (sit in names(sim_it2$sim_list_converted)) {
    write.table(sim_it2$sim_list_converted[[sit]],
                file = file.path(daily_outdir_it2, paste0("sit",sit,".txt")), 
                quote=FALSE, row.names = FALSE)
  }
  
  
  
}


generate_cal_results <- function(sim_final, obs_list, obsVar_units, obsVar_used, 
                                 sitNames_corresp, template_path, out_dir, test_case, 
                                 variety,varNames_corresp, resVar_names, file_type,
                                 use_obs_synth=FALSE, sim_true=NULL, descr_ref_date=NULL,
                                 flag_obs_mat=TRUE, flag_eos) {
  
  # Convert simulations to observation space (names of situations and variables, units) if necessary
  if (is.null(sim_final$sim_list_converted)) {
    sim_final_converted <- sim_final
    if (!is.null(sitNames_corresp))
      sim_final_converted$sim_list <- rename_sit(sim_final_converted$sim_list, 
                                                 sitNames_corresp, invert=FALSE)
    sim_final_converted$sim_list <- set_units(sim_final_converted$sim_list, simVar_units)
    sim_final_converted$sim_list <- rename_var(sim_final_converted$sim_list, 
                                               varNames_corresp, invert=FALSE)
    sim_final_converted$sim_list <- convert_units(sim_final_converted$sim_list, obsVar_units)
    sim_final_converted$sim_list  <- lapply(sim_final_converted$sim_list ,drop_units)
    attr(sim_final_converted$sim_list, "class") <- "cropr_simulation"
  } else {
    sim_final_converted <- sim_final
    sim_final_converted$sim_list <- sim_final_converted$sim_list_converted
  }
    
  # Compute stats criteria
  stats <- summary(sim_final_converted$sim_list, obs=obs_list, stats=c("MSE", "Bias2","SDSD","LCS"))
  write.table(dplyr::select(stats,-group, -situation),
              file = file.path(out_dir,"stats.txt"),row.names = FALSE, quote=FALSE)
  
  
  # Generate the required results file
  
  ## Read the template
  template_df <- read.table(template_path,
                            header = TRUE, stringsAsFactors = FALSE)
  if ("Date_sowing" %in% names(template_df)) {
    template_df_ext <- template_df %>% 
      mutate(year_sowing=year(as.Date(Date_sowing, format = "%d/%m/%Y")),
             Origin=as.Date(paste0(year_sowing-1,"-12-31"))) %>% 
      mutate(Date=as.Date(Date, format = "%d/%m/%Y")) 
  } else {
    template_df_ext <- template_df %>% 
      mutate(year_sowing=year(as.Date(SowingDate, format = "%d/%m/%Y")),
             Origin=as.Date(paste0(year_sowing-1,"-12-31"))) %>% 
      mutate(Date=as.Date(Date, format = "%d/%m/%Y")) 
  } 
  
  ## Retrieve harvest year
  harvest_year <- setNames(template_df$HarvestYear[!duplicated(template_df$Number)], 
                           template_df$Number[!duplicated(template_df$Number)])
  
  ## Create a mask for extracting required values from simulations
  ## The mask is equal to observed list for the situations of the calibration dataset 
  ## + required variables at HARVEST for the situations of the evaluation dataset
  mask <- obs_list
  mask <- lapply(mask, function(x) {x[,resVar_names] <- 0; return(x)}) # add required variables if necessary
  mask <- lapply(mask, function(x) { # remove non-required variables
    x[setdiff(names(x), c("Date",resVar_names))] <- NULL; return(x)
  }) 
  for (sit in setdiff(as.character(template_df_ext$Number),names(obs_list))) {
    mask[[sit]] <- dplyr::filter(template_df_ext,Number==sit) %>% dplyr::select(Date, dplyr::all_of(resVar_names))
    mask[[sit]][,resVar_names] <- 0
  }

  
  # Handle the retrieval of end-of-season results both for calibration and evaluation datasets 
  # depending on the options chosen.
  ref_date <- get_reference_date(descr_ref_date, template_path)
  for (sit in names(mask)) {
    if (flag_obs_mat) {
      # eos_date is set to observed value of maturity date
      # jul_BBCH90 <- tail(sim_true$sim_list_converted[[sit]]$Date_BBCH90,n=1)
      jul_BBCH90 <- tail(obs_list[[sit]]$Date_BBCH90,n=1)
      if (is.null(jul_BBCH90)) jul_BBCH90 <- NA
    } else {
      # eos_date is set to simulated value of maturity date
      jul_BBCH90 <- tail(sim_final$sim_list[[sitNames_corresp[[sit]]]][[varNames_corresp[["Date_BBCH90"]]]],n=1)
    }

    if (is.na(jul_BBCH90) || flag_eos) { 
      # set eos_date to 31/12/harvestYear
      harvestYear <- harvest_year[[sit]]
      eos_Date <- as.Date(paste0(harvestYear,"-12-31"), format="%Y-%m-%d")[[1]]
      # except for "Lake_2010_***" since there's not enough weather data ...
      if (sit %in% names(sitNames_corresp[grep("Lake-2010",sitNames_corresp)])) {
        eos_Date <- as.Date("2011-01-30", format="%Y-%m-%d")[[1]]
      }
    } else {
      eos_Date <- as.Date(as.numeric(jul_BBCH90),
                          origin=ref_date[[sit]],
                          format="%Y-%m-%d")[[1]]    
    }    
    
    mask[[sit]][nrow(mask[[sit]]),"Date"] <- eos_Date
    
    ## check that the maturity date is posterior to the last observation date ...
    ## in this case warn the user and set harvest date later
    if (nrow(mask[[sit]]) > 1) {
      if (mask[[sit]][nrow(mask[[sit]]),"Date"] <= mask[[sit]][nrow(mask[[sit]])-1,"Date"]) {
        mask[[sit]][nrow(mask[[sit]]),"Date"] <- mask[[sit]][nrow(mask[[sit]])-1,"Date"] + 5
      }
    }
  }
  
  ## Intersect mask and simulated values
  obs_sim_list <- CroptimizR:::make_obsSim_consistent(sim_final_converted$sim_list,  
                                                      mask)
  res <- CroptimizR:::intersect_sim_obs(sim_list = obs_sim_list$sim_list,
                                        obs_list = obs_sim_list$obs_list)
  res_df <- CroPlotR::bind_rows(res$sim_list)
  res_df <- mutate(res_df, Number=as.integer(situation)) %>% select(-situation)
  
  ## Add information from the template file
  template_df_ext <- slice(template_df_ext, which(!duplicated(template_df_ext$Number)))
  res_df <- left_join(res_df, select(template_df_ext, Number,
                                     setdiff(names(template_df_ext), names(res_df))), 
                      by="Number") 
  
  ## Convert julian days in Dates
  var_date <- names(res_df)[grepl("Date_",names(res_df))]   # TODO : change if HarvestDate is required ...
  res_df <- res_df %>% 
    mutate(Origin=ref_date[as.character(res_df$Number)]) %>% 
    rowwise() %>% mutate(across(all_of(var_date), ~ case_when(.==0 ~ as.character(NA), 
                                                              .!=0 ~ format(as.Date(.x, 
                                                                                    origin=Origin),"%d/%m/%Y")))) %>%
    select(-Origin, -year_sowing) %>% relocate(names(template_df))
  
  
  
  suffix <- NULL
  if (test_case=="French") suffix <- paste0("_",variety) 
  write.table(res_df,file = file.path(out_dir,paste0("cal_4_results_", test_case, 
                                                     suffix, "_", file_type, 
                                                     "_", model_name, ".txt")),
              row.names = FALSE, quote=FALSE)
  
}



generate_obs_file <- function(obs_list, obsVar_units, obsVar_used, 
                              sitNames_corresp, template_path, out_dir, test_case, 
                              variety, varNames_corresp, resVar_names, file_type) {
  
  # Generate obs files for synthetic experiments
  
  ## Read the template
  template_df <- read.table(template_path,
                            header = TRUE, stringsAsFactors = FALSE)
  if ("Date_sowing" %in% names(template_df)) {
    template_df_ext <- template_df %>% 
      mutate(year_sowing=year(as.Date(Date_sowing, format = "%d/%m/%Y")),
             Origin=as.Date(paste0(year_sowing-1,"-12-31"))) %>% 
      mutate(Date=as.Date(Date, format = "%d/%m/%Y")) 
  } else {
    template_df_ext <- template_df %>% 
      mutate(year_sowing=year(as.Date(SowingDate, format = "%d/%m/%Y")),
             Origin=as.Date(paste0(year_sowing-1,"-12-31"))) %>% 
      mutate(Date=as.Date(Date, format = "%d/%m/%Y")) 
  } 
  
  ## Retrieve information from obs_list
  res_df <- CroPlotR::bind_rows(obs_list, .id="situation")
  res_df <- mutate(res_df, Number=as.integer(situation)) %>% select(-situation)

  ## Add information from the template file
  template_df_ext <- slice(template_df_ext, which(!duplicated(template_df_ext$Number)))
  res_df_full <- left_join(res_df, select(template_df_ext, Number,
                                          setdiff(names(template_df_ext), names(res_df))), 
                           by="Number") 
    
  ## Retrieve information about Harvest date in res_df (= Date of synth obs, defined from synth TRUE obs ...)
  index <- which(!duplicated(res_df$Number, fromLast = TRUE))
  shifted_index <- shift(index)
  shifted_index[1] <- 0
  res_df_full$HarvestDate <- rep(res_df$Date[index],index-shifted_index)
  res_df_full$HarvestYear <- year(res_df_full$HarvestDate)
  
  ## Convert julian days in Dates
  var_date <- names(res_df)[grepl("Date_",names(res_df))]   
  if ("Date_sowing" %in% names(res_df_full)) {
    res_df_full <- rename(res_df_full, Date_sowing="SowingDate")
  }
  res_df_full <- res_df_full %>% 
    mutate(year_sowing=year(as.Date(SowingDate, format = "%d/%m/%Y")),
           Origin=as.Date(paste0(year_sowing-1,"-12-31"))) %>% 
    rowwise() %>% mutate(across(all_of(var_date), ~ case_when(.==0 ~ as.character(NA), 
                                                              .!=0 ~ format(as.Date(.x, 
                                                                                    origin=Origin),"%d/%m/%Y")))) %>%
    select(-Origin, -year_sowing) %>% relocate(names(template_df))
  
  suffix <- NULL
  if (test_case=="French") suffix <- paste0("_",variety) 
  write.table(res_df_full,file = file.path(out_dir,paste0("cal_4_obs_", test_case, 
                                                     suffix, "_", file_type, "_", 
                                                     model_name, ".txt")),
              row.names = FALSE, quote=FALSE)
  
}


generate_parameters_table <- function(res, group_names, forced_param_values) {
  table <- bind_rows(lapply(names(res$final_values), function(param) {
    setNames(
      tibble(group_names[param],
             param,
			 forced_param_values[param],
             res$init_values[res$ind_min_crit, param],
             res$final_values[param]),
      nm=c("Name of the group","Name of the estimated parameter","Default value",
             "Selected initial value", "Final value")
    )
  }))
  
  return(table)
}


save_table <- function (table, table_name, path) {
  
  tb <- purrr::modify_if(
    table,
    function(x) !is.list(x), as.list
  )
  # format everything in char and 2 digits
  tb <- purrr::modify(
    tb,
    function(x) {
      unlist(
        purrr::modify(x, function(y) {
          paste(format(y,
                       scientific = FALSE,
                       digits = 2, nsmall = 2
          ), collapse = ", ")
        })
      )
    }
  )
  
  utils::write.table(tb,
                     sep = ";", file = file.path(
                       path,
                       paste0(table_name,".csv")
                     ),
                     row.names = FALSE
  )
  
}