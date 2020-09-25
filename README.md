# uRxtr-Modeling

This repository contains various tools generated as part of a 2019-2020 study of
microreactor deployment at US Gov't facilities.

## Economic Analysis

This script performs a net present value analysis for different combinations of
technologies operating on different system design scenarios.  It can calculate
results for single instances of cost assumptions, perform sensitivity analysis
to those assumptions, or generate Monte Carlo distributions.

## HOMER Dispatch Model via Matlab

These scripts use HOMER's coupling to Matlab to enable a customized dispatch
strategy, largely to overcome a bug in HOMER's currently available options.