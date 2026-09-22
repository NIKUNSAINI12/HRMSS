using System.Net;
using System.Net.Mail;
using System.Threading.Tasks;
using Microsoft.Extensions.Configuration;

public class EmailService
{
    private readonly string smtpServer;
    private readonly int smtpPort;
    private readonly string smtpUser;
    private readonly string smtpPass;

    public EmailService(IConfiguration configuration)
    {
        smtpServer = configuration["EmailSettings:SmtpServer"];
        smtpPort = int.Parse(configuration["EmailSettings:SmtpPort"]);
        smtpUser = configuration["EmailSettings:SmtpUser"];
        smtpPass = configuration["EmailSettings:SmtpPass"];
    }

    public async Task<bool> SendEmailAsync(string toEmail, string subject, string body)
    {
        try
        {
            using (var client = new SmtpClient(smtpServer, smtpPort))
            {
                client.UseDefaultCredentials = false;
                client.Credentials = new NetworkCredential(smtpUser, smtpPass);
                client.EnableSsl = true;
                client.DeliveryMethod = SmtpDeliveryMethod.Network;

                var mailMessage = new MailMessage
                {
                    From = new MailAddress(smtpUser),
                    Subject = subject,
                    Body = body,
                    IsBodyHtml = true,
                };
                mailMessage.To.Add(toEmail);

                await client.SendMailAsync(mailMessage);
            }
            
            // Log Success
            var p = new Dapper.DynamicParameters();
            p.Add("@TOAddress", toEmail);
            p.Add("@TOSubject", subject);
            p.Add("@MailBody", body);
            p.Add("@status", 1);
            p.Add("@ErrorMsg", string.Empty);
            HRMSWebAPI.Helper.DataBaseFactory.QuerySP("SAL_Email_Log_Ins", p, "GetAll");

            return true; // Email sent successfully
        }
        catch (Exception ex)
        {
            // Log Error
            var p = new Dapper.DynamicParameters();
            p.Add("@TOAddress", toEmail);
            p.Add("@TOSubject", subject);
            p.Add("@MailBody", body);
            p.Add("@status", 0);
            p.Add("@ErrorMsg", ex.Message);
            HRMSWebAPI.Helper.DataBaseFactory.QuerySP("SAL_Email_Log_Ins", p, "GetAll");

            Console.WriteLine($"Error sending email: {ex.Message}");
            return false; // Email sending failed
        }
    }
}
