'use strict';



/**
 * Dashboard controller
 */
angular.module('calcentral.controllers').controller('DashboardController', function(apiService, linkService, $scope) {

  var init = function() {
    linkService.addCurrentRouteSettings($scope);
    apiService.util.setTitle($scope.currentPage.name);
    if (!apiService.user.profile.hasDashboardTab) {
      apiService.user.redirectToHome();
    }
  };

  $scope.redirectToHome = function() {
    apiService.util.redirectToHome();
    return false;
  };

  // We have to watch the user profile for changes because of async loading in
  // case of Back button navigation from a different (non-CalCentral) location.
  $scope.$watch('api.user.profile.hasDashboardTab', init);
});
