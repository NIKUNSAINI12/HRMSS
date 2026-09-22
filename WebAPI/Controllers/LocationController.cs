using HRMSWebAPI.Models;
using HRMSWebAPI.Repository;
using Microsoft.AspNetCore.Mvc;

namespace HRMSWebAPI.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    [Microsoft.AspNetCore.Authorization.AllowAnonymous]
    public class LocationController : ControllerBase
    {
        private readonly ILocationRepository _repository;

        public LocationController(ILocationRepository repository)
        {
            _repository = repository;
            _repository.EnsureTableExists();
        }

        [HttpPost("update")]
        public IActionResult UpdateLocation([FromBody] LocationUpdateDto dto)
        {
            if (dto == null) return BadRequest("Invalid location data");

            var record = _repository.AddLocation(dto);
            return Ok(new { success = true, recordId = record.Id, istTime = record.ServerReceivedAt });
        }

        [HttpGet("history")]
        public IActionResult GetHistory([FromQuery] string? userId = null, [FromQuery] int limit = 100)
        {
            var history = _repository.GetHistory(userId, limit);
            return Ok(history);
        }

        [HttpGet("stats")]
        public IActionResult GetStats()
        {
            var stats = _repository.GetStats();
            return Ok(stats);
        }

        [HttpPost("clear")]
        public IActionResult ClearHistory()
        {
            _repository.ClearStore();
            return Ok(new { success = true, message = "Location history cleared from SQL Server" });
        }
    }
}
