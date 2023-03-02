# load environment variables from .env file
load-env-file () 
{
	local file=$1
	if [ ! -f $file ]; 
	then 
		echo "File not found"
	else
		set -o allexport
		source $file
		set +o allexport
		echo "Loaded environment"
	fi
}
