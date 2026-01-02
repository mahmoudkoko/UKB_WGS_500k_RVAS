# Data analysis on UK RAP


## Using the GUI


### Exploring genetic variants


### Cohorts


### Table Exporter


### URL Fetcher


There is a tool called ‘URL Fetcher’ which is intended to download data from the internet to your Analysis Project. It actually works by starting a linux machine, downloading the data to that machine, then uploading it to your project directory on RAP, following the same logic we explained above. That is why you will be limited by the size of the disk space attached to your virtual machine, not the space on the Data platform (which is technically unlimited). If you run the tool with a disk space that is smaller than your file, it will fail.


## Using the command line


### DX command line client

DX clients allow your terminal device (laptop/desktop) to communicate with the RAP platform.

While you do not neccessarily need DX client to work with UKB RAP (see TTYD below), it offers versatile and convenient functions to submit jobs and explore meta-data as well as to upload and download files from and to your local machine. 


Python-based DX client is available through `pip install dxpy`. It will automatically install a shell-based client that you can access by running `dx` command from bash/zsh or similar shells. Note that there are other clients for R, Java and C++.


#### Installation

The instructions for installing DX client [can be found here](https://documentation.dnanexus.com/downloads#dnanexus-platform-sdk). Set up differs slightly between `zsh` and other shells. 


This is an example for `bash` on Ubuntu(-based) Linux to give an overview.


Insure you have access to pip `which pip3`. If not available, install with

```bash
sudo apt install python3-pip
```

Ideally, use a virtual enviroment to avoid issues with conflicts and updates.


Here we will use `python3-venv` to install the client in a virtual enviroment on a desktop/laptop. Skip to the installation if you want to install system-wide


```bash
sudo apt install python3-venv
```

Create a virtual env for dxpy in a location of your choosing, e.g.,

```bash
python3 -m venv ${HOME}/.local/venv/dxpy
```

Activate this environment


```bash
source ${HOME}/.local/venv/dxpy/bin/activate
```

Install `dxpy`

```bash
pip install dxpy
```

Enable auto-complete

```bash
eval "$(register-python-argcomplete dx | sed 's/-o default//')"
```

Now the client should be in your path:


```bash
dx --version
```


To deactivate the enviroment


```bash
deactivate
```


This should work with Windows Subsystem for Linux (WSL) as well.


If you are on an HPC, you might need to load a specific module (e.g., `module load dxpy`). Use `module avail` or `module list` to see if its there. 

If not available, you can install locally (see above) but again you might need to load pip or python (e.g., `module load pip` or `module load python3.xx`).


On MacOS, you should be able to install locally using `pip install dxpy` in bash or zsh. It will be located in `${HOME}/Library/Python/3.xx/bin/`. You can add that to your PATH.


TO DO: add windows.



#### Login and configuration


You might want to check if DX client is installed and active (e.g., by running `which dx`).


To login (you will be prompted to prove your credentials)


```bash
dx login
```


By default, you will remain logged-in for 30 days. That means, if you have an active login from a previous session on the same device, you will not need to login again for 30 days.


To select the default project for your CLI


```bash
dx select
```

To see what is in this project, list the files and directories


```bash
dx ls
```

To set up your ssh key

```bash
dx ssh_config
```


Depending on how you installed DX, you may need to activate the environment or a module.



### Using 'vanilla' Virtual Machines


There are two applications to start an empty linux machine:

- Cloud Workstation.
- ttyd.

Both do the same in terms of starting a linux VM. The workstation app will allow you to ssh from your local shell to this VM  (e.g., using the Terminal app in MacOS, Linux or Windows Subsystem for Linux). The 'ttyd' app will start a terminal over the web and your 'CLI' will be visible on a browser page (useful if you do not have a terminal at hand, e.g., on Windows).  


To start the cloud workstation app from the command line, use `dx` to submit a job (activate your dxpy environment if needed and login, then set up the ssh key using `dx ssh_config`. Select the correct project if needed).


```bash
dx run app-cloud_workstation \
--instance-type mem1_ssd1_v2_x2 \
--priority high \
--ssh \
--brief
```

Select other options if desired (e.g. session length). The list of options can be obtained by running 

```bash
dx run app-cloud_workstation --help
```

You will be connected to the VM over ssh once it is ready.

To start a VM with terminal over the browser, use `ttyd`

```bash
dx run app-ttyd \
--instance-type mem1_ssd1_v2_x2 \
--priority high \
--brief
```

You can start Cloud Workstation and TTYD VMs from the GUI by looking for these apps in the Tools Library and following the instructions. 


The terminal for TTYD will be on `https://${DX_JOBID}.dnanexus.cloud` (there will be a link on the Monitor tab). You will need to use `dx ssh ${DX_JOBID}` to connect to a Clound Workstation (you can do the same and connect to TTYD). In practice, however, there is little value in starting the Cloud Workstation from the GUI (you need `dx` to ssh anyway) or starting TTYD from the CLI (the terminal is on the GUI anyway).

If you can install `dxpy` or have `dx` already, you should use the workstation (slightly cheaper). TTYD is typically used when you don't have access to a terminal on your laptop/desktop or when you can't install `dxpy` for any reason.


When you are inside the VM, the terminal session is managed using `byobu` and `tmux`. Instead of opening several ssh connections from your local terminal, this setup allows you to have multiple sessions. This is a short list of what you can do:
- Detach the active session using `tmux detach`.
- Create new sessions with `tmux new -s ${your_session_name}`.
- Attach them with `tmux attach -t ${session_name}`.
- List sessions with `tmux ls`.
- Kill sessions with `tmux kill-session`.


Within a session, you can have multiple windows. You can swith between these windows using F3/F4. To create new windows, press F2.

You can terminate the VM using `dx terminate $DX_JOBID` or from the Monitor tab on the GUI.

TO DO: download and upload. Snapshots. Examples for simple commands to get phenotypic data.


#### Extract phenotypes


#### Upload agent



### RStudio and Jupyter Notebooks 

While you can run R and Python on a vanilla VM, you might want the flexibility and convenience of Rstudio and Jupyter Notebooks.

Posit Workbench (Rstudio) app will request a virtual machine with a certain set of resources, which you have to indicate, and will run an Rstudio server on it. You will then be able to open it in the browser.


JupyterLab (Notebook) app will set up a Jupyter server on a virtual machine and connect you to that. There are several presets that you can use including support for Spark clusters.


Note that Rstudio and Jupyter have terminals so you can also use them to run shell commands and scripts if needed. (I personally find this easier than using `dxpy` or `dxR`.


### Swiss-Army-Knife 

TBD

### other tools

TBD


## Designing tools

Users can design and compile their own tools as apps (tools that will be stored permanently on RAP, including across projects if you choose so) or applets (smaller apps that live within your analysis project only). 

Applets and apps that are private to your project will be saved as files on your project directory and will run when you click on them directly on the GUI. They will also be listed along with all available tools when you select a project and click on 'Start Analysis' (on the right-hand side of the sub-panel of 'Manage').



