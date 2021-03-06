reliabilityFrequentist <- function(jaspResults, dataset, options) {


  dataset <- .reliabilityReadData(dataset, options)
  .reliabilityCheckErrors(dataset, options)

  model <- .frequentistReliabilityMainResults(jaspResults, dataset, options)

  .frequentistReliabilityScaleTable(         jaspResults, model, options)
  .frequentistReliabilityItemTable(          jaspResults, model, options)
  .freqentistReliabilitySingleFactorFitTable(jaspResults, model, options)
  return()

}

# read data, check errors----
.frequentistReliabilityDerivedOptions <- function(options) {

  # order of appearance in Bayesrel
  derivedOptions <- list(
    selectedEstimatorsF  = unlist(options[c("mcDonaldScale","alphaScale", "guttman2Scale", "guttman6Scale",
                                            "glbScale", "averageInterItemCor", "meanScale", "sdScale")]),
    itemDroppedSelectedF = unlist(options[c("mcDonaldItem", "alphaItem", "guttman2Item", "guttman6Item",
                                            "glbItem", "itemRestCor", "meanItem", "sdItem")]),
    namesEstimators     = list(
      tables = c("McDonald's \u03C9", "Cronbach's \u03B1", "Guttman's \u03BB2", "Guttman's \u03BB6",
                 "Greatest Lower Bound", "Average interitem correlation", "mean", "sd"),
      tables_item = c("McDonald's \u03C9", "Cronbach's \u03B1", "Guttman's \u03BB2", "Guttman's \u03BB6",
                      gettext("Greatest Lower Bound"), gettext("Item-rest correlation"), gettext("mean"), gettext("sd")),
      coefficients = c("McDonald's \u03C9", "Cronbach's \u03B1", "Guttman's \u03BB2", "Guttman's \u03BB6",
                       gettext("Greatest Lower Bound")),
      plots = list(expression("McDonald's"~omega), expression("Cronbach\'s"~alpha), expression("Guttman's"~lambda[2]),
                   expression("Guttman's"~lambda[6]), gettext("Greatest Lower Bound"))
    )
  )

  return(derivedOptions)
}



# estimate reliability ----
# maybe in the future it would be easier to have one function for every estimator...
.frequentistReliabilityMainResults <- function(jaspResults, dataset, options) {
  if (!options[["mcDonaldScale"]] && !options[["alphaScale"]] && !options[["guttman2Scale"]]
      && !options[["guttman6Scale"]] && !options[["glbScale"]] && !options[["averageInterItemCor"]]
      && !options[["meanScale"]] && !options[["sdScale"]]
      && !options[["itemRestCor"]] && !options[["meanItem"]] && !options[["sdItem"]]) {
    variables <- options[["variables"]]
    if (length(options[["reverseScaledItems"]]) > 0L) {
      dataset <- .reverseScoreItems(dataset, options)
    }
    model <- list()
    model[["footnote"]] <- .reliabilityCheckLoadings(dataset, variables)
    return(model)
  }
  model <- jaspResults[["modelObj"]]$object
  relyFit <- model[["relyFit"]]
  if (is.null(model)) {

    model <- list()
    variables <- options[["variables"]]

    samples <- options[["noSamples"]]
    p <- ncol(dataset)

    if (length(variables) > 2L) {

      if (length(options[["reverseScaledItems"]]) > 0L) {
        dataset <- .reverseScoreItems(dataset, options)
      }

      # observations for alpha interval need to be specified:
      model[["obs"]] <- nrow(dataset)

      model[["footnote"]] <- .reliabilityCheckLoadings(dataset, variables)
      if (any(is.na(dataset))) {
        if (options[["missingValues"]] == "excludeCasesPairwise") {
          missing <- "pairwise"
          use.cases <- "pairwise.complete.obs"
          model[["footnote"]] <- gettextf("%s Of the observations, pairwise complete cases were used. ",
                                          model[["footnote"]])
        } else {
          pos <- which(is.na(dataset), arr.ind = TRUE)[, 1]
          dataset <- dataset[-pos, ]
          use.cases <- "complete.obs"
          model[["footnote"]] <- gettextf("%s Of the observations, %1.f complete cases were used. ",
                                          model[["footnote"]], nrow(dataset))
        }
      } else {
        use.cases <- "everything"
      }

      if (options[["alphaInterval"]] == "alphaAnalytic") {
        alphaAna <- TRUE
        alphaSteps <- 0
      } else {
        alphaAna <- FALSE
        alphaSteps <- samples
        if (options[["alphaMethod"]] == "alphaStand") {
          alphaSteps <- alphaSteps + samples
        }
      }

      if (options[["omegaEst"]] == "pfa") {
        omegaSteps <- samples
        omegaAna <- FALSE
      } else {
        if (options[["omegaInterval"]] == "omegaAnalytic") {
          omegaAna <- TRUE
          omegaSteps <- 0
        } else {
          omegaAna <- FALSE
          omegaSteps <- 0
          # omegaSteps <- samples  # not working because we cannot tick in the bootstrapLavaan function
        }
      }

      if (options[["bootType"]] == "bootNonpara") {
        para <- FALSE
      } else {
        para <- TRUE
      }

      if (options[["intervalOn"]]) { # with confidence interval:

        startProgressbar(samples * 5 # cov_mat bootstrapping and coefficients (also avg_cor) without alpha and omega
                         + alphaSteps
                         + omegaSteps) # dont need ifitem steps since that is very fast
        if (options[["setSeed"]]) {
          set.seed(options[["seedValue"]])
        }

        if (options[["alphaMethod"]] == "alphaStand") {
          model[["dat_cov"]] <- Bayesrel:::make_symmetric(cov2cor(cov(dataset, use = use.cases)))
          relyFit <- try(Bayesrel::strel(data = dataset, estimates=c("lambda2", "lambda6", "glb", "omega"),
                                         Bayes = FALSE, n.boot = options[["noSamples"]],
                                         item.dropped = TRUE, omega.freq.method = options[["omegaEst"]],
                                         omega.int.analytic = omegaAna,
                                         para.boot = para,
                                         missing = missing, callback = progressbarTick))
          relyFit[["freq"]][["est"]][["freq_alpha"]] <- Bayesrel:::applyalpha(model[["dat_cov"]])

          relyFit[["freq"]][["ifitem"]][["alpha"]] <- numeric(p)
          for (i in 1:p){
            relyFit[["freq"]][["ifitem"]][["alpha"]][i] <- Bayesrel:::applyalpha(model[["dat_cov"]][-i, -i])
          }

          # when standardized alpha, but bootstrapped alpha interval:
          if (!alphaAna) {
            relyFit[["freq"]][["boot"]][["alpha"]] <- numeric(options[["noSamples"]])
            for (i in 1:options[["noSamples"]]) {
              relyFit[["freq"]][["boot"]][["alpha"]][i] <- Bayesrel:::applyalpha(.cov2cor.callback(relyFit[["freq"]][["covsamp"]][i, , ], progressbarTick))
            }
          }

        } else { # alpha unstandardized
          model[["dat_cov"]] <- Bayesrel:::make_symmetric(cov(dataset, use = use.cases))
          relyFit <- try(Bayesrel::strel(data = dataset, estimates=c("alpha", "lambda2", "lambda6", "glb", "omega"),
                                         Bayes = FALSE, n.boot = options[["noSamples"]],
                                         item.dropped = TRUE, omega.freq.method = options[["omegaEst"]],
                                         alpha.int.analytic = alphaAna,
                                         omega.int.analytic = omegaAna,
                                         para.boot = para,
                                         missing = missing, callback = progressbarTick))

        }

        # first the scale statistics
        cordat <- cor(dataset, use = use.cases)
        relyFit[["freq"]][["est"]][["avg_cor"]] <- mean(cordat[lower.tri(cordat)])
        relyFit[["freq"]][["est"]][["mean"]] <- mean(rowMeans(dataset, na.rm = T))
        relyFit[["freq"]][["est"]][["sd"]] <- sd(colMeans(dataset, na.rm = T))

        relyFit[["freq"]][["boot"]][["avg_cor"]] <- numeric(options[["noSamples"]])
        for (i in 1:options[["noSamples"]]) {
          corm <- .cov2cor.callback(relyFit[["freq"]][["covsamp"]][i, , ], progressbarTick)
          relyFit[["freq"]][["boot"]][["avg_cor"]][i] <- mean(corm[corm!=1])
        }
        relyFit[["freq"]][["boot"]][["mean"]] <- c(NA_real_, NA_real_)
        relyFit[["freq"]][["boot"]][["sd"]] <- c(NA_real_, NA_real_)


        # now the item statistics
        relyFit[["freq"]][["ifitem"]][["ircor"]] <- numeric(p)
        for (i in 1:ncol(dataset)) {
          relyFit[["freq"]][["ifitem"]][["ircor"]][i] <- cor(dataset[, i], rowMeans(dataset[, -i], na.rm = T), use = use.cases)
        }
        relyFit[["freq"]][["ifitem"]][["mean"]] <- colMeans(dataset, na.rm = T)
        relyFit[["freq"]][["ifitem"]][["sd"]] <- apply(dataset, 2, sd, na.rm = T)

        # reorder for JASP
        names_est <- names(relyFit[["freq"]][["est"]])
        order_est <- c("freq_omega", "freq_alpha", "freq_lambda2", "freq_lambda6", "freq_glb",
                       "avg_cor", "mean", "sd")
        new_order_est <- match(order_est, names_est)
        relyFit[["freq"]][["est"]] <- relyFit[["freq"]][["est"]][new_order_est]

        names_item <- names(relyFit[["freq"]][["ifitem"]])
        order_item <- c("omega", "alpha", "lambda2", "lambda6", "glb",
                       "ircor", "mean", "sd")
        new_order_item <- match(order_item, names_item)
        relyFit[["freq"]][["ifitem"]] <- relyFit[["freq"]][["ifitem"]][new_order_item]

        # free some memory
        relyFit[["freq"]][["covsamp"]] <- NULL
        relyFit[["data"]] <- NULL

        # ------------------------ only point estimates, no intervals: ---------------------------
      } else {
        relyFit <- list()
        cv <- Bayesrel:::make_symmetric(cov(dataset, use = use.cases))
        cordat <- cor(dataset, use = use.cases)
        p <- ncol(dataset)
        Cvtmp <- array(0, c(p, p - 1, p - 1))
        for (i in 1:p){
          Cvtmp[i, , ] <- cv[-i, -i]
        }

        if (options[["omegaEst"]] == "pfa") {
          omega.est <- Bayesrel:::applyomega_pfa(cv)
          omega.item <- apply(Cvtmp, 1, Bayesrel:::applyomega_pfa)
        } else {
          if (use.cases == "pairwise.complete.obs") {
            omega <- Bayesrel:::omegaFreqData(dataset, interval=.95, omega.int.analytic = T, pairwise = T)
            omega.est <- omega[["omega"]]
            if (is.na(omega.est)) {
              omega.est <- Bayesrel:::applyomega_pfa(cv)
              relyFit[["freq"]][["omega.error"]] <- TRUE
            } else {
              relyFit[["freq"]][["omega.fit"]] <- omega[["indices"]]
            }
            omega.item <- numeric(p)
            for (i in 1:p) {
              omega.item[i] <- Bayesrel:::applyomega_cfa_data(as.matrix(dataset[, -i]), interval = .95, pairwise = T)
              if (is.na(omega.item[i])) {
                omega.item <- apply(Cvtmp, 1, Bayesrel:::applyomega_pfa)
                relyFit[["freq"]][["omega.item.error"]] <- TRUE
                break
              }
            }


          } else {
            omega <- Bayesrel:::omegaFreqData(dataset, interval=.95, omega.int.analytic = T, pairwise = F)
            omega.est <- omega[["omega"]]
            if (is.na(omega.est)) {
              omega.est <- Bayesrel:::applyomega_pfa(cv)
              relyFit[["freq"]][["omega.error"]] <- TRUE
            } else {
              relyFit[["freq"]][["omega.fit"]] <- omega[["indices"]]
            }

            omega.item <- numeric(p)
            for (i in 1:p) {
              omega.item[i] <- Bayesrel:::applyomega_cfa_data(as.matrix(dataset[, -i]), interval = .95, pairwise = F)
              if (is.na(omega.item[i])) {
                omega.item <- apply(Cvtmp, 1, Bayesrel:::applyomega_pfa)
                relyFit[["freq"]][["omega.item.error"]] <- TRUE
                break
              }
            }
          }
        }
        if (options[["alphaMethod"]] == "alphaStand") {
          ca <- Bayesrel:::make_symmetric(cov2cor(cv))
          alpha <- Bayesrel:::applyalpha(ca)
          alpha.item <- numeric(p)
          for (i in 1:p){
            alpha.item <- Bayesrel:::applyalpha(ca[-i, -i])
          }
        } else {
          alpha <- Bayesrel:::applyalpha(cv)
          alpha.item <- apply(Cvtmp, 1, Bayesrel:::applyalpha)

        }

        relyFit[["freq"]][["est"]] <- list(freq_omega = omega.est, freq_alpha = alpha,
                                 freq_lambda2 = Bayesrel:::applylambda2(cv), freq_lambda6 = Bayesrel:::applylambda6(cv),
                                 freq_glb = Bayesrel:::glbOnArray(cv), avg_cor = mean(cordat[lower.tri(cordat)]),
                                 mean = mean(rowMeans(dataset, na.rm = TRUE)), sd = sd(colMeans(dataset, na.rm = TRUE)))

        relyFit[["freq"]][["ifitem"]] <- list(omega = omega.item, alpha = alpha.item,
                                          lambda2 = apply(Cvtmp, 1, Bayesrel:::applylambda2),
                                          lambda6 = apply(Cvtmp, 1, Bayesrel:::applylambda6),
                                          glb = apply(Cvtmp, 1, Bayesrel:::glbOnArray))
        relyFit[["freq"]][["ifitem"]][["ircor"]] <- NULL
        for (i in 1:ncol(dataset)) {
          relyFit[["freq"]][["ifitem"]][["ircor"]][i] <- cor(dataset[, i], rowMeans(dataset[, -i], na.rm = TRUE), use = use.cases)
        }
        relyFit[["freq"]][["ifitem"]][["mean"]] <- colMeans(dataset, na.rm = TRUE)
        relyFit[["freq"]][["ifitem"]][["sd"]] <- apply(dataset, 2, sd, na.rm = TRUE)
      }


      # free some memory
      relyFit[["data"]] <- NULL
      relyFit[["freq"]][["covsamp"]] <- NULL

      if (inherits(relyFit, "try-error")) {

        model[["error"]] <- paste(gettext("The analysis crashed with the following error message:\n", relyFit))

      } else {

        model[["dataset"]] <- dataset

        model[["relyFit"]] <- relyFit

        stateObj <- createJaspState(model)
        stateObj$dependOn(options = c("variables", "reverseScaledItems", "noSamples", "missingValues", "omegaEst",
                                        "alphaMethod", "alphaInterval", "omegaInterval", "bootType",
                                        "setSeed", "seedValue", "intervalOn"))

        jaspResults[["modelObj"]] <- stateObj

      }
    }
  }

  if (is.null(model[["error"]])) {
    if (options[["intervalOn"]]) {
      cfiState <- jaspResults[["cfiObj"]]$object
      if (is.null(cfiState) && !is.null(relyFit)) {
        scaleCfi <- .frequentistReliabilityCalcCfi(relyFit[["freq"]][["boot"]],
                                                   options[["confidenceIntervalValue"]])
        # alpha int is analytical, not from the boot sample, so:
        if (options[["alphaInterval"]] == "alphaAnalytic") {

          alphaCfi <- Bayesrel:::ciAlpha(1 - options[["confidenceIntervalValue"]], model[["obs"]], model[["dat_cov"]])
          names(alphaCfi) <- c("lower", "upper")
          scaleCfi[["alpha"]] <- alphaCfi
        }

        # omega cfa analytic interval:
        if (is.null(relyFit[["freq"]][["omega.pfa"]]) && (options[["omegaInterval"]] == "omegaAnalytic")) {
          fit <- relyFit[["freq"]][["fit.object"]]

          params <- lavaan::parameterestimates(fit, level = options[["confidenceIntervalValue"]])
          om_low <- params$ci.lower[params$lhs=="omega"]
          om_up <- params$ci.upper[params$lhs=="omega"]
          omegaCfi <- c(om_low, om_up)
          names(omegaCfi) <- c("lower", "upper")
          scaleCfi[["omega"]] <- omegaCfi
        }
        # reorder for JASP:
        names_cfi <- names(scaleCfi)
        order_cfi <- c("omega", "alpha", "lambda2", "lambda6", "glb",
                        "avg_cor", "mean", "sd")
        new_order_cfi <- match(order_cfi, names_cfi)
        scaleCfi <- scaleCfi[new_order_cfi]

        cfiState <- list(scaleCfi = scaleCfi)
        jaspCfiState <- createJaspState(cfiState)
        jaspCfiState$dependOn(options = "confidenceIntervalValue", optionsFromObject = jaspResults[["modelObj"]])
        jaspResults[["cfiObj"]] <- jaspCfiState
      }
      model[["cfi"]] <- cfiState
      progressbarTick()
    }
  }

  model[["derivedOptions"]] <- .frequentistReliabilityDerivedOptions(options)
  model[["itemsDropped"]] <- .unv(colnames(dataset))

  # when variables are deleted again, a model footnote is expected, but none produce, hence:
  if (is.null(model[["footnote"]])) model[["footnote"]] <- ""

  return(model)
}

.frequentistReliabilityCalcCfi <- function(boot, cfiValue) {

  cfi <- vector("list", length(boot))
  names(cfi) <- names(boot)
  for (nm in names(boot)) {
    if (nm %in% c("mean", "sd"))
      cfi[[nm]] <- c(NA_real_, NA_real_)
    else if (all(is.na(boot[[nm]])))
      cfi[[nm]] <- c(NaN, NaN)
    else
      cfi[[nm]] <- quantile(boot[[nm]], prob = c((1-cfiValue)/2, 1-(1-cfiValue)/2), na.rm = TRUE)

    names(cfi[[nm]]) <- c("lower", "upper")
  }
  return(cfi)
}



# tables ----


.frequentistReliabilityScaleTable <- function(jaspResults, model, options) {
  if (!is.null(jaspResults[["scaleTable"]])) {
    return()
  }
  scaleTable <- createJaspTable(gettext("Frequentist Scale Reliability Statistics"))
  scaleTable$dependOn(options = c("variables", "mcDonaldScale", "alphaScale", "guttman2Scale", "guttman6Scale",
                                   "glbScale", "reverseScaledItems", "confidenceIntervalValue", "noSamples",
                                   "averageInterItemCor", "meanScale", "sdScale", "missingValues", "omegaEst",
                                   "alphaMethod", "alphaInterval", "omegaInterval", "bootType",
                                   "setSeed", "seedValue", "intervalOn"))
  scaleTable$addColumnInfo(name = "estimate", title = gettext("Estimate"), type = "string")



  if (options[["intervalOn"]]) {
    intervalLow <- gettextf("%s%% CI",
                            format(100*options[["confidenceIntervalValue"]], digits = 3, drop0trailing = TRUE))
    intervalUp <- gettextf("%s%% CI",
                           format(100*options[["confidenceIntervalValue"]], digits = 3, drop0trailing = TRUE))
    intervalLow <- gettextf("%s lower bound", intervalLow)
    intervalUp <- gettextf("%s upper bound", intervalUp)
    allData <- data.frame(estimate = c(gettext("Point estimate"), intervalLow, intervalUp))
  } else {
    allData <- data.frame(estimate = c(gettext("Point estimate")))
  }

# if no coefficients selected:
  if ((!options[["mcDonaldScale"]] && !options[["alphaScale"]] && !options[["guttman2Scale"]]
       && !options[["guttman6Scale"]] && !options[["glbScale"]] && !options[["averageInterItemCor"]]
       && !options[["meanScale"]] && !options[["sdScale"]])) {

    scaleTable$setData(allData)
    nvar <- length(options[["variables"]])
    if (nvar > 0L && nvar < 3L)
      scaleTable$addFootnote(gettextf("Please enter at least 3 variables to do an analysis. %s", model[["footnote"]]))
    else
      scaleTable$addFootnote(model[["footnote"]])
    jaspResults[["scaleTable"]] <- scaleTable
    scaleTable$position <- 1
    return()
  }


  relyFit <- model[["relyFit"]]
  derivedOptions <- model[["derivedOptions"]]
  opts     <- derivedOptions[["namesEstimators"]][["tables"]]
  selected <- derivedOptions[["selectedEstimatorsF"]]
  idxSelected <- which(selected)

  if (options[["mcDonaldScale"]] && !is.null(relyFit[["freq"]][["omega.error"]])) {
    model[["footnote"]] <- gettextf("%1$sMcDonald's %2$s estimation method switched to PFA because the CFA
                                    did not find a solution. ", model[["footnote"]], "\u03C9")
  }

  if (!is.null(relyFit)) {


    if (options[["intervalOn"]]) {
      addSingularFootnote <- FALSE
      for (i in idxSelected) {
        scaleTable$addColumnInfo(name = paste0("est", i), title = opts[i], type = "number")
        newData <- data.frame(est = c(unlist(relyFit[["freq"]][["est"]][[i]], use.names = F),
                                      unlist(model[["cfi"]][["scaleCfi"]][[i]], use.names = F)))
        colnames(newData) <- paste0(colnames(newData), i)
        allData <- cbind(allData, newData)

        # produce footnote for coefficients that are prone to fail with singular matrices, such as lambda6 and omega
        if (any(is.nan(model[["cfi"]][["scaleCfi"]][[i]])))
          addSingularFootnote <- TRUE
      }
      if (addSingularFootnote) {
        model[["footnote"]] <- gettextf("%s Some confidence intervals could not be computed because none of the bootstrapped covariance matrices were invertible.", model[["footnote"]])
      }

    } else {
      for (i in idxSelected) {
        scaleTable$addColumnInfo(name = paste0("est", i), title = opts[i], type = "number")
        newData <- data.frame(est = c(unlist(relyFit[["freq"]][["est"]][[i]], use.names = F)))
        colnames(newData) <- paste0(colnames(newData), i)
        allData <- cbind(allData, newData)
      }
    }

    scaleTable$setData(allData)

    if (!is.null(model[["footnote"]]))
      scaleTable$addFootnote(model[["footnote"]])
  } else if (sum(selected) > 0L) {

    for (i in idxSelected) {
      scaleTable$addColumnInfo(name = paste0("est", i), title = opts[i], type = "number")
    }
    nvar <- length(options[["variables"]])
    if (nvar > 0L && nvar < 3L){
      scaleTable$addFootnote(gettext("Please enter at least 3 variables to do an analysis."))
    }

  }
  if (!is.null(model[["error"]]))
    scaleTable$setError(model[["error"]])

  if (!is.null(model[["footnote"]]))
    scaleTable$addFootnote(model[["footnote"]])

  jaspResults[["scaleTable"]] <- scaleTable
  scaleTable$position <- 1

  return()
}


.frequentistReliabilityItemTable <- function(jaspResults, model, options) {

  if (!is.null(jaspResults[["itemTable"]]) || !any(model[["derivedOptions"]][["itemDroppedSelectedF"]])) {
    return()
  }

  derivedOptions <- model[["derivedOptions"]]
  # fixes issue that unchecking the scale coefficient box, does not uncheck the item-dropped coefficient box:
  for (i in 1:5) {
    if (!derivedOptions[["selectedEstimatorsF"]][i]) {
      derivedOptions[["itemDroppedSelectedF"]][i] <- derivedOptions[["selectedEstimatorsF"]][i]
    }
  }
  itemDroppedSelectedF <- derivedOptions[["itemDroppedSelectedF"]]
  estimators <- derivedOptions[["namesEstimators"]][["tables_item"]]
  overTitle <- gettext("If item dropped")

  itemTable <- createJaspTable(gettext("Frequentist Individual Item Reliability Statistics"))
  itemTable$dependOn(options = c("variables",
                                  "mcDonaldScale", "alphaScale", "guttman2Scale", "guttman6Scale", "glbScale",
                                  "averageInterItemCor", "meanScale", "sdScale",
                                  "mcDonaldItem",  "alphaItem",  "guttman2Item", "guttman6Item", "glbItem",
                                  "reverseScaledItems", "meanItem", "sdItem", "itemRestCor", "missingValues",
                                  "omegaEst", "alphaMethod", "setSeed", "seedValue"))
  itemTable$addColumnInfo(name = "variable", title = gettext("Item"), type = "string")

  idxSelectedF <- which(itemDroppedSelectedF)
  coefficients <- derivedOptions[["namesEstimators"]][["coefficients"]]
  for (i in idxSelectedF) {
    if (estimators[i] %in% coefficients) {
      itemTable$addColumnInfo(name = paste0("pointEst", i), title = estimators[i], type = "number",
                               overtitle = overTitle)
    } else {
      itemTable$addColumnInfo(name = paste0("pointEst", i), title = estimators[i], type = "number")
    }
  }

  relyFit <- model[["relyFit"]]

  if (!is.null(relyFit)) {
    if (options[["mcDonaldScale"]] && !is.null(relyFit[["freq"]][["omega.item.error"]])) {
      itemTable$addFootnote(gettextf("McDonald's %s estimation method for item-dropped statistics switched to PFA because the CFA did not find a solution.","\u03C9"))
    }

    tb <- data.frame(variable = model[["itemsDropped"]])
    for (i in idxSelectedF) {
      newtb <- cbind(pointEst = relyFit[["freq"]][["ifitem"]][[i]])
      colnames(newtb) <- paste0(colnames(newtb), i)
      tb <- cbind(tb, newtb)

    }
    itemTable$setData(tb)

    if (!is.null(unlist(options[["reverseScaledItems"]]))) {
      itemTable$addFootnote(sprintf(ngettext(length(options[["reverseScaledItems"]]),
                                             "The following item was reverse scaled: %s. ",
                                             "The following items were reverse scaled: %s. "),
                                    paste(options[["reverseScaledItems"]], collapse = ", ")))
    }

  } else if (length(model[["itemsDropped"]]) > 0) {
    itemTable[["variables"]] <- model[["itemsDropped"]]

    if (!is.null(unlist(options[["reverseScaledItems"]]))) {
      itemTable$addFootnote(sprintf(ngettext(length(options[["reverseScaledItems"]]),
                                             "The following item was reverse scaled: %s. ",
                                             "The following items were reverse scaled: %s. "),
                                    paste(options[["reverseScaledItems"]], collapse = ", ")))
    }
  }

  jaspResults[["itemTable"]] <- itemTable
  itemTable$position <- 2

  return()
}

# once the package is updated check this again and apply:
.freqentistReliabilitySingleFactorFitTable <- function(jaspResults, model, options) {

  if (!options[["fitMeasures"]] || !options[["mcDonaldScale"]] || options[["omegaEst"]]=="pfa")
    return()
  if (!is.null(jaspResults[["fitTable"]]) || !options[["fitMeasures"]]) {
    return()
  }

  fitTable <- createJaspTable(gettextf("Fit Measures of Single Factor Model Fit"))
  fitTable$dependOn(options = c("variables", "mcDonaldScale", "reverseScaledItems", "fitMeasures", "missingValues",
                                "omegaEst", "setSeed", "seedValue"))
  fitTable$addColumnInfo(name = "measure", title = gettext("Fit Measure"),   type = "string")
  fitTable$addColumnInfo(name = "value",  title = gettext("Value"), type = "number")

  relyFit <- model[["relyFit"]]
  derivedOptions <- model[["derivedOptions"]]
  opts <- names(relyFit[["freq"]][["omega_fit"]])

  if (!is.null(relyFit)) {
    if (is.null(opts)) {
      allData <- data.frame(
        measure = NA_real_,
        value = NA_real_
      )
      if (!is.null(relyFit[["freq"]][["omega.error"]])) {
          fitTable$addFootnote(gettextf("Fit measures cannot be displayed because the McDonald's %s estimation method switched to PFA as the CFA did not find a solution.","\u03C9"))
      }
    } else {
      opts <- c("Chi-Square", "df", "p.value", "RMSEA", "Lower CI RMSEA", "Upper CI RMSEA", "SRMR")
      allData <- data.frame(
        measure = opts,
        value = as.vector(unlist(relyFit[["freq"]][["omega_fit"]], use.names = FALSE))
      )
    }

    fitTable$setData(allData)
  }
  if (!is.null(model[["error"]]))
    fitTable$setError(model[["error"]])


  jaspResults[["fitTable"]] <- fitTable
  fitTable$position <- 3

}



# get bootstrapped sample for omega with cfa
.applyomega_cfa_cov <- function(cov, n){
  data <- MASS::mvrnorm(n, numeric(ncol(cov)), cov)
  out <- Bayesrel:::omegaFreqData(data, pairwise = F)
  om <- out[["omega"]]
  return(om)
}

