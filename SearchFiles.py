#!/data/xnat/scripts/venv/bin/python3
# encoding: utf-8

"""
A collection of functions that will copy DICOM images from an instance of a XNAT server
between Carle Hospital and the University of Illinois at Urbana-Champaign (UIUC).

These images will be transferred via Globus timer to the UIUC's globus endpoint and 
later transferred to the XNAT server instance at the UIUC.
"""

# Modules
import git
import time
import sys
from shutil import copy2
import shutil
from pathlib import Path
import pathlib
import os
import glob
import datetime
import tempfile
import logging

__author__ = "Jose Villamizar"
__copyright__ = "Copyright 2021, University of Illinois at Urbana-Champaign - Beckman Institute for Advanced Science and Technology"
__credits__ = ["Dean Karres", "Neil Thackeray"]
__license__ = "GPL"
__version__ = "1.0"
__maintainer__ = "Jose Villamizar"
__email__ = "josev2@illinois.edu"
__status__ = "Development"

# Specified time period to copy DICOM images to NetApp cifs share
seconds_per_day = 3600 * 24
one_day_ago = time.time() - seconds_per_day
two_days_ago = time.time() - (seconds_per_day * 2)

# initialization of variables
total_size = 0
studies_keys = {}
paths_to_copy = {}
match_studies = []
studies_to_find = []
server_name = os.uname()[1]

# Source directory, location of the cloned file from GitHub and destination of the DICOM images
search_path = '/data/xnat/archive/'
studies_path = '/data/xnat/scripts/xnat_Carle2Illinois.txt'
target_directory = '/netappcifs'


LOGGER = logging.getLogger("SearchFiles_{}".format(__version__))

def main():
    """
    Main function that will gather information of the source directories
    and evaluate number of files changed within the time period specified.

    Args:

    return:
        This will return a list of the fullpath of the files to be copied.
    """

    global count
    global file_sizes
    global total_studies_matched
    files_per_study = {}

    count = 0
    file_sizes = 0
    total_size = 0

    try:

        for path in get_current_dirnames(search_path, studies_path):

            for file in pathlib.Path(path).glob('**/*'):
                try:
                    file_stat = os.stat(file)
                    studies_keys[os.path.basename(path)] = True

                except FileNotFoundError:
                    continue

                if not os.path.isdir(file) and file_stat.st_mtime >= one_day_ago:
                    count += 1
                    studies = Path(file).parts[4]

                    if studies not in files_per_study:
                        files_per_study[studies] = []
                    relative_path = '/'.join(Path(file).parts[4:])

                    files_per_study[studies].append({
                        'src': file,
                        'dest': os.path.join(target_directory, relative_path)})

                    paths_to_copy[file.as_posix()] = True

                    # contains individual file sizes of the files changed within the time specified
                    file_sizes += os.path.getsize(file)

                    # contains the total file sizes of the files changed within the time specified
                    total_size = get_human_readable(file_sizes)

    except Exception as e:
        raise Exception('Main: ' + repr(e))

    if(count is None or count == 0):
        quit()
    else:
        print('\n'.join(list(paths_to_copy.keys())))
        print('Studies: ', files_per_study.keys())
        print("Files per study: ", files_per_study)
        print("We found [ " + format(count,",") +
           " ] file(s) changed within a day.")
        print("The study [" + studies + "] has a total size of [" + total_size + "]")
        return files_per_study

def get_current_dirnames(search_path, studies_path):
    """
    This function will extract the study name from the studies.txt file

    The studies.txt file will be formatted as follows:

    Principal Investigator's name/Study Name,Principal Investigator's name/Study name

    Jose_Villamizar/CUPS,Aaron_Anderson/CUPS

    Args:

    	:param search_path source directory of the studies on the XNAT server. Usually located in /data/xnat/archive

    	:param studies_path file downloaded from Github repo

    Return:

	return the path of the studies matched against the studies file downloaded from GitHub
    """

    current_studies_dirnames = os.listdir(search_path)
    total_number_dirnames = len(current_studies_dirnames)
    print("We found [" + format(total_number_dirnames,",") + "] study names on the server " + server_name)
    print(current_studies_dirnames)
    new_search_path = []

    try:
        with open(studies_path, 'r') as studies_textfile:
            try:
                studies_to_search = studies_textfile.readlines()
                studies_to_search = set(item.rstrip() for item in studies_to_search)
                studies_to_search = set(item.rsplit("/")[-1] for item in studies_to_search)
                new_search_path = [os.path.join(search_path,x) for x in current_studies_dirnames if x in studies_to_search]
                total_studies_matched = len(new_search_path)
            except FileNotFoundError as e:
                print(f"File can't be read {repr(e)}")
            finally:
                studies_textfile.close()
    except Exception as e:
        raise Exception('get_current_dirnames: ' + repr(e))

    if(total_studies_matched is None or total_studies_matched == 0):
        quit()
    else:
        return new_search_path

def get_file_from_git():
    """
    Git function that will download a file named xnat_Carle2Illinois.txt that contain a list
    of the studies performed during the last 24 hours.

    Args:

    Return:

        The list of studies to be transfer from source to remote destination
    """

    try:
        # Destination of the cloned repo file
        destination = '/data/xnat/scripts/'

        # Check to see if destination folder exists and remove it
        if os.path.isdir(destination) is False:
            os.makedirs(destination)

        # Create a temporary directory to download the file from github
        temp_dir = tempfile.mkdtemp(dir=destination)

        # Clone github repo into temporary directory
        git.Repo.clone_from('https://github.com/aaronta/CIAIC_sync.git',
                            temp_dir, branch='main', depth=1)

        # Copy studies.txt file from temporary directory
        final_source = os.path.join(temp_dir, 'xnat_Carle2Illinois.txt')
        final_destination = os.path.join(destination, 'xnat_Carle2Illinois.txt')
        git_studies_file = shutil.move(final_source, final_destination)

        # Change permissions on files
        recursive_chown(temp_dir)

        # Remove temporary directory
        shutil.rmtree(temp_dir)
    except Exception as e:
        raise Exception('get_file_from_git: ' + repr(e))

    return git_studies_file


def matched_studies(files_per_study):
    """
    Match studies submitted via Github file

    Args:

        :param files_per_study
    """

    try:
        with open(studies_path) as studies_to_find:
            try:
                match_studies = studies_to_find.readlines()
                match_studies = set(item.rsplit("/")[-1] for item in match_studies)
                print('Submitted Studies: ', match_studies)

                for m in match_studies:
                    print('Current Study: ', m)

                    m = m.strip()
                    if m in files_per_study:
                        print("Files per study: ", files_per_study[m])
                        for f in files_per_study[m]:
                            print('Matched:', f['src'])
                            copy_files(f)

            except FileNotFoundError as e:
                print(f"No studies file has been found. {repr(e)}")
            finally:
                studies_to_find.close()
    except Exception as e:
        print(repr(e))


def copy_files(target_file):
    """
    Copy files modified within 24 hours to a target destination

    Args:
        :param target_directory: contains the fullpath of the destination folder

    Returns:
        the list of files copied to the destination folder.

    """
    try:
        # check to see if destination folder exists
        if not os.path.exists(target_directory):

            try:
                os.makedirs(target_directory)
            except OSError as e:
                if e.errno != errno.EEXIST:
                    raise OSError(
                        'Failed to create directory ' + target_directory)

        # copy files to destination folder
        print("Copying files to: ", target_file)
        if not os.path.isdir(os.path.dirname(target_file['dest'])):
            os.makedirs(os.path.dirname(target_file['dest']))
        shutil.copy2(target_file['src'].as_posix(), target_file['dest'])
        recursive_chown(target_directory)

    except Exception as e:
        raise Exception("copy_files: ", repr(e))


def recursive_chown(target_directory, recursive=True):
    """
    Change user uid and gid to match remote XNAT's server file(s) permissions.

    Args:
        :param target_directory Path of target directory
        :param bool recursive: set files/dirs recursively
    """
    user = 1001            # uid for user xnat on XNAT server
    group = 1001           # gid for user xnat on XNAT server

    try:
        if not recursive or os.path.isfile(target_directory):
            shutil.chown(target_directory, user, group)
        else:
            for root, dirs, files in os.walk(target_directory):
                shutil.chown(root, user, group)
                for item in dirs:
                    shutil.chown(os.path.join(root, item), user, group)
                for item in files:
                    shutil.chown(os.path.join(root, item), user, group)
    except OSError as e: 
        raise Exception('recursive_chown: ' + repr(e))


def get_human_readable(size, precision=2):
    """
    function that express the amount of data using the best possible unit

    Args:
        :param size size of the files or directories
        :param precision number of decimal places

    return:
        return the size of the files/directories using the best unit of measurement
    """

    try:

        suffixes = [' B', ' MB', ' GB', ' TB', ' PB', ' EB']
        suffixIndex = 0
        while size > 1024 and suffixIndex < 7:
            suffixIndex += 1
            size = size / 1024.0
    except Exception as e:
       raise Exception('get_human_readable: ' + repr(e))
       return "%.*f%s" % (precision, size, suffixes[suffixIndex])


def logger():
    """ 
    Logging function None = 0, Debug = 10, Info = 20, Warning = 30,  Error = 40, Critical = 50
    """
    logging.basicConfig(
    level=logging.DEBUG,
    format="{asctime} {levelname}:<8} {message}",
    style='{',
    filename='%slog' % __file__[:-2],
    filemode='w'
)

    logging.debug('File will be copied')
    logging.info('File copying')
    logging.warning('File will be attempted to be copy')
    logging.error('File was not copied')


if __name__ == '__main__':
    get_file_from_git()
    x = main()
    matched_studies(x)
