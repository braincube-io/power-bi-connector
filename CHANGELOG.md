# Changelog

## [3.0.1]

### Fixed

- [#5335](https://gitlab.ipleanware.com/braincube/misc/redmine/-/issues/5335) All memoryBase and all variables are not retrieve
  correctly.

## [3.0.0]

### Added

- changelog file
- gitlab.ci to push tag in mattermost

### Changed

- The period selector with end and begin date are replaced by a sliding period (Ex: Last 30 days).
  Now after configuration of the query, on each open it the data are updated with the sliding period, after use "Refresh" button.
  _ If the data are getted by connector are DATETIME, we convert her for PowerBi detect it like a datetime.

## [2.0.0] - 2021-03

### Changed

- using ApiKey connection

## [1.0.0] - 2018-06

- Initial version of project, using Oauth connection
    
