#!/bin/bash
#SBATCH -J sarek
#SBATCH --partition acpu
#SBATCH --account=<allocation>
#SBATCH -o log/sarek_%j.out  # Output file with the job ID
#SBATCH -e log/sarek_%j.err  # Error file with the job ID
#SBATCH -t 24:00:00   # Set the wall time: D-HH:MM:SS
#SBATCH --qos=cpu-normal
#SBATCH -n 1 -c 2  # ask for number of nodes/cores
#SBATCH --mem=18GB  # Specify memory allocation

set -euo pipefail

: "${scrproj:?Set scrproj to the scratch project directory}"
: "${pipelinepath:?Set pipelinepath to the Nextflow pipeline path}"
: "${samplefile:?Set samplefile to the Sarek sample sheet}"
: "${pipeoutdir:?Set pipeoutdir to the pipeline output directory}"

# make software accessible:
module load nextflow/23.04
module load singularity/3.7.4

echo ____________________________________
nextflow -version
echo ____________________________________
singularity --version
echo ____________________________________


## Override defaults set by nextflow module:
export NXF_WORK="$scrproj/work"
export NXF_TEMP="$scrproj/tmp"
export NXF_HOME="/projects/$USER/software/nextflow_config"
export _JAVA_OPTIONS='-Xmx16G' # increase heap to avoid java.lang.OutOfMemoryError



nextflow run "$pipelinepath"  -ansi-log false \
	--input "$samplefile" --trim_fastq \
	--save_trimmed --save_mapped --save_output_as_bam --outdir "$pipeoutdir" \
	--tools mutect2,strelka,tiddit,freebayes,vep,snpeff -resume \
	-c curc_alpine.config,fastp.config
