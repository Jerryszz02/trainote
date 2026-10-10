/** Parse the deployment-owned opt-in without treating "false" or typos as truthy. */
export function developmentBuildsAllowed(value: string | undefined): boolean {
  if (value === undefined || value === 'false') return false;
  if (value === 'true') return true;
  throw new Error('invalid_configuration:APPLE_ALLOW_DEVELOPMENT_BUILDS');
}
