# Genome-wide rare variant association analysis in UK Biobank

For an overview of the biobank and available data visit: [`ukbiobank.ac.uk`](https://www.ukbiobank.ac.uk/)


UK Biobank data is stored centrally and made available to users through the [**Research Analysis Platform**](https://ukbiobank.dnanexus.com/login). You will need to set up access and then request a copy of the UK Biobank data. Analyses are then performed on RAP using your dispensed copy of UK Biobank data. There are limits on what can be downloaded from RAP (only de-identified summaries). You can upload your own data (e.g., annotations or summary statistics needed for your analysis). Analysis are performed using tools (applications or applets) and workflows (several tools). You can work from the terminal or the browser; serious use requires familiarity with bash, python, or R (support for Java, C, and others exists).


## General introductions and documentations


Details on available UKB data are provided in this ‘Showcase’: [`https://biobank.ndph.ox.ac.uk/showcase/`](https://biobank.ndph.ox.ac.uk/showcase/)

This is useful to explore or look up variables, field names, etc. For example, if you search for ‘exome’, it will give you a list of all ‘fields’ related to exomes. 

Technical documentation on the analysis platform is available here: [`https://dnanexus.gitbook.io/uk-biobank-rap`](https://dnanexus.gitbook.io/uk-biobank-rap)

DNANexus also has a technical documentation for their platform, which applies largely to UKBRAP as well: [`https://documentation.dnanexus.com/`](https://documentation.dnanexus.com/)


You might also be interested in reading the introductions provided with this repository:

- [Finding your way around](./docs/UKB_intro_to_platform.md)
- [Performing analysis](./docs/UKB_intro_to_analysis.md)


## WGS burden analysis


## Overview

TBD

## Using applets from this repository


Insure you have access to git (`which git`) and dx client (`which dx`). 

Clone this repository somewhere


```bash
cd "${HOME}/Documents/"

git clone https://github.com/mahmoudkoko/UKB_WGS_500k_RVAS.git
```

Move to the repo

```bash
cd "${HOME}/Documents/UKB_WGS_500k_RVAS"
```



Applets will be under `applets`


```bash
ls "${HOME}/Documents/UKB_WGS_500k_RVAS/applets/"
```


Insure you are logged in to RAP via the terminal (`dx login`), that you are in the correct project (`dx select`) and that you have set your ssh configurations (`dx ssh_config`).


Create a target directory in your analysis project

```bash
dx mkdir "Applets"
```


Compile with `dx build`. The option `-f` will overwrite any previous versions from the same applet in this directory. 

```bash
dx build -f -d "Applets/" ./applets/${desired_applet_dir}
```

This will print a few lines of JSON to the screen including the applet ID.

You can copy it and save it as a variable (e.g., `your_applet_id=applet-xxxxxxxxxxxxxx`).

To capture it automatically

```bash
dx build --brief -f -d "Applets/" ./applets/${desired_applet_dir} | jq - 
```


Now this applet will be availble to you to run either from the GUI (by clicking on it) or via CLI (using dx).


The options available with each applet will vary depending on the applet setup but in general it will look like this:


```bash
dx run ${your_applet_id} \
--destination "project-id-token:/output_dir/" \
--instance-type "mem1_ssd1_v2_x2" \
--name "The name you would like to see on the GUI for this submission" \
--priority high
```

